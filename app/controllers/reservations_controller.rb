# app/controllers/reservations_controller.rb

class ReservationsController < ApplicationController
  include TenantIsolation
  
  # Only staff/admin can do index/show/update/destroy
  # but 'create' is public (no login required).
  before_action :authorize_request, except: [:create]
  before_action :ensure_tenant_context

  def index
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    # Prepare filter parameters
    filter_params = {}
    
    if params[:date].present?
      # Handle both simple string and nested parameter formats
      date_param = params[:date].is_a?(ActionController::Parameters) ? params[:date][:date] : params[:date]
      filter_params[:date] = date_param
    end
    
    # Add other filters if present
    [:status, :customer_name, :phone, :email, :page, :per_page, :location_id].each do |param|
      filter_params[param] = params[param] if params[param].present?
    end
    
    # Debug log to verify location_id is being forwarded properly
    Rails.logger.debug "Reservation filter params: #{filter_params.inspect}"
    
    result = reservation_service.list_reservations(filter_params)
    
    if result[:success]
      render json: result[:reservations].as_json(
        only: [
          :id, :restaurant_id, :start_time, :end_time, :party_size,
          :contact_name, :contact_phone, :contact_email,
          :deposit_amount, :reservation_source, :special_requests,
          :status, :created_at, :updated_at, :duration_minutes,
          :seat_preferences, :location_id, :reservation_number
        ],
        methods: :seat_labels,
        include: { location: { only: [:id, :name] } }
      )
    else
      render json: { error: result[:errors].join(', ') }, status: result[:status] || :internal_server_error
    end
  end

  def show
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    result = reservation_service.find_reservation(params[:id])
    
    if result[:success]
      render json: result[:reservation].as_json(
        only: [
          :id, :restaurant_id, :start_time, :end_time, :party_size,
          :contact_name, :contact_phone, :contact_email,
          :deposit_amount, :reservation_source, :special_requests,
          :status, :created_at, :updated_at, :duration_minutes,
          :seat_preferences, :reservation_number
        ],
        methods: :seat_labels
      )
    else
      render json: { error: result[:errors].join(', ') }, status: result[:status] || :not_found
    end
  end

  # Public create
  def create
    # For public endpoint, ensure tenant context is properly validated
    # Check if restaurant_id is provided and exists
    restaurant_id = reservation_params[:restaurant_id]
    
    if restaurant_id.blank?
      # For public API, ensure restaurant_id is always present
      return render json: { error: "Restaurant ID is required" }, status: :unprocessable_entity
    end
    
    # Verify restaurant exists
    restaurant = Restaurant.find_by(id: restaurant_id)
    unless restaurant
      return render json: { error: "Restaurant not found" }, status: :unprocessable_entity
    end
      
    # Set the current restaurant context for this request
    @current_restaurant = restaurant
    
    # Prepare the reservation data
    create_params = {}
    
    # Process start_time
    if reservation_params[:start_time].present?
      parsed_start = Time.zone.parse(reservation_params[:start_time])
      if parsed_start.nil?
        return render json: { error: "Invalid start_time format" }, status: :unprocessable_entity
      end
      create_params[:start_time] = parsed_start
    else
      return render json: { error: "start_time is required" }, status: :unprocessable_entity
    end
    
    # Process end_time if provided, or calculate it from restaurant's configured duration
    if reservation_params[:end_time].present?
      parsed_end = Time.zone.parse(reservation_params[:end_time])
      return render json: { error: "Invalid end_time format" }, status: :unprocessable_entity if parsed_end.nil?
      create_params[:end_time] = parsed_end
    else
      # Always use the restaurant's configured duration
      # Get from admin_settings.reservations.duration_minutes if available, fallback to reservation_duration property
      restaurant_duration = restaurant.admin_settings&.dig("reservations", "duration_minutes") || 
                           restaurant.reservation_duration || 
                           60 # Default to 60 minutes if not set
      
      # Use the restaurant's duration even if client provided duration_minutes
      if reservation_params[:duration_minutes].present? && reservation_params[:duration_minutes].to_i != restaurant_duration
        # Log that we're overriding the client-provided duration
        Rails.logger.info "Overriding client-provided duration: #{reservation_params[:duration_minutes]} with restaurant setting: #{restaurant_duration} minutes"
      end
      
      create_params[:end_time] = create_params[:start_time] + restaurant_duration.minutes
      create_params[:duration_minutes] = restaurant_duration
      
      Rails.logger.info "Using restaurant-configured duration: #{restaurant_duration} minutes to calculate end_time: #{create_params[:end_time]}"
    end
    
    # Copy other parameters
    [:party_size, :contact_name, :contact_phone, :contact_email, 
     :deposit_amount, :reservation_source, :special_requests, 
     :status, :seat_preferences].each do |field|
      create_params[field] = reservation_params[field] if reservation_params[field].present?
    end
    
    # Handle location_id specially to verify it exists and belongs to this restaurant
    if reservation_params[:location_id].present?
      location_id = reservation_params[:location_id].to_i
      location = restaurant.locations.find_by(id: location_id)
      
      if location
        Rails.logger.info "Using specified location: #{location.name} (ID: #{location.id})"
        create_params[:location_id] = location.id
      else
        Rails.logger.warn "Location ID #{location_id} not found for restaurant #{restaurant.id}, using default location"
        # Let the model's set_default_location callback handle it
      end
    end
    
    # Set restaurant_id - use the validated restaurant context
    create_params[:restaurant_id] = restaurant.id
    
    # Set status to booked if not provided
    create_params[:status] ||= 'booked'
    
    # Check capacity using the service, including location_id when available
    if exceeds_capacity?(restaurant, create_params[:start_time], create_params[:end_time], create_params[:party_size], create_params[:location_id])
      return render json: { error: "Not enough seats for that timeslot" }, status: :unprocessable_entity
    end
    
    # Use service to create the reservation with proper tenant isolation
    result = reservation_service.create_reservation(create_params)
    
    if result[:success]
      reservation = result[:reservation]
      
      # Handle notifications
      notification_channels = restaurant.admin_settings&.dig("notification_channels", "reservations") || {}

      # Optionally send a creation email - send unless explicitly disabled
      if notification_channels["email"] != false && reservation.contact_email.present?
        # Send booking creation email instead of confirmation
        ReservationMailer.booking_created(reservation).deliver_later
      end

      # Optionally send a text message - send unless explicitly disabled
      if notification_channels["sms"] != false && reservation.contact_phone.present?
        restaurant_name = restaurant.name
        # Use custom SMS sender ID if set, otherwise use restaurant name
        sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name

        # Prepare location string if needed
        location_str = ""
        if reservation.location.present? && restaurant.locations.count > 1 && reservation.location.name != restaurant_name
          location_str = " at #{reservation.location.name}"
        end
        
        message_body = <<~MSG.squish
          Hi #{reservation.contact_name}, your #{restaurant_name}#{location_str} reservation request has been received
          for #{reservation.start_time.strftime("%B %d at %I:%M %p")} (party of #{reservation.party_size}).
          We'll confirm your reservation shortly.
        MSG
        
        # Use background job for SMS sending instead of direct call
        # This improves API response time by offloading SMS sending to a worker
        SendSmsJob.perform_later(
          to:   reservation.contact_phone,
          body: message_body,
          from: sms_sender
        )
        
        # Log that SMS was enqueued but not sent synchronously
        Rails.logger.info("SMS notification for reservation ##{reservation.id} enqueued to background job")
      end
      
      render json: reservation.as_json(
        only: [
          :id, :restaurant_id, :start_time, :end_time, :party_size,
          :contact_name, :contact_phone, :contact_email,
          :deposit_amount, :reservation_source, :special_requests,
          :status, :created_at, :updated_at, :duration_minutes,
          :seat_preferences, :location_id, :reservation_number
        ],
        methods: :seat_labels
      ), status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def update
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    # Use the reservation service for proper tenant scoping
    result = reservation_service.update_reservation(params[:id], reservation_params)
    
    if result[:success]
      # Check if this is a status change to 'reserved' (confirmation)
      # and if so, send confirmation notifications
      if reservation_params[:status] == 'reserved'
        reservation = result[:reservation]
        restaurant = reservation.restaurant
        
        # Only proceed with notifications if we have a valid restaurant
        if restaurant.present?
          # Get notification settings from restaurant
          notification_channels = restaurant.admin_settings&.dig("notification_channels", "reservations") || {}
          
          # Send confirmation email
          if notification_channels["email"] != false && reservation.contact_email.present?
            ReservationMailer.booking_confirmation(reservation).deliver_later
            Rails.logger.info("Confirmation email for reservation ##{reservation.id} enqueued")
          end
          
          # Send confirmation SMS
          if notification_channels["sms"] != false && reservation.contact_phone.present?
            restaurant_name = restaurant.name
            # Use custom SMS sender ID if set, otherwise use restaurant name
            sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name
            
            # Prepare location string if needed
            location_str = ""
            if reservation.location.present? && restaurant.locations.count > 1 && reservation.location.name != restaurant_name
              location_str = " at #{reservation.location.name}"
            end
            
            message_body = <<~MSG.squish
              Hi #{reservation.contact_name}, your #{restaurant_name}#{location_str} reservation has been confirmed
              for #{reservation.start_time.strftime("%B %d at %I:%M %p")} (party of #{reservation.party_size}).
              #{reservation.deposit_amount && reservation.deposit_amount > 0 ? "Deposit amount: $#{sprintf("%.2f", reservation.deposit_amount.to_f)}. " : ""}
              We look forward to seeing you!
            MSG
            
            # Use background job for SMS sending
            SendSmsJob.perform_later(
              to:   reservation.contact_phone,
              body: message_body,
              from: sms_sender
            )
            
            Rails.logger.info("Confirmation SMS for reservation ##{reservation.id} enqueued")
          end
        end
      end
      
      render json: result[:reservation].as_json(
        only: [
          :id, :restaurant_id, :start_time, :end_time, :party_size,
          :contact_name, :contact_phone, :contact_email,
          :deposit_amount, :reservation_source, :special_requests,
          :status, :created_at, :updated_at, :duration_minutes,
          :seat_preferences, :location_id, :reservation_number
        ],
        methods: :seat_labels
      ), status: :ok
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def destroy
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    # Use the reservation service for proper tenant scoping
    result = reservation_service.delete_reservation(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def public_endpoint?
    # Allow public access to the reservations endpoints
    # For index and other actions, we need to ensure the user has a valid restaurant context
    # or is a super_admin with a restaurant_id parameter
    if action_name == 'create'
      return true
    elsif current_user
      if current_user.role == 'super_admin'
        return params[:restaurant_id].present?
      else
        return %w[admin staff].include?(current_user.role) && current_user.restaurant_id.present?
      end
    end
    false
  end

  def reservation_params
    allowed = params.require(:reservation).permit(
      :restaurant_id,
      :start_time,
      :end_time,
      :party_size,
      :contact_name,
      :contact_phone,
      :contact_email,
      :deposit_amount,
      :reservation_source,
      :special_requests,
      :status,
      :duration_minutes,
      :location_id
      # Not seat_preferences here
    )

    # Manually insert seat_preferences if present
    if params[:reservation].key?(:seat_preferences)
      allowed[:seat_preferences] = params[:reservation][:seat_preferences]
    end

    allowed
  end

  def exceeds_capacity?(restaurant, start_dt, end_dt, new_party_size, location_id = nil)
    # Validate input parameters
    new_party_size = new_party_size.to_i
    
    # Get total seat capacity, using location-specific seats when a location_id is provided
    seats = if location_id.present?
      restaurant.location_seats(location_id)
    else
      restaurant.current_seats
    end
    
    # Calculate total capacity by summing seat capacities, not just counting seats
    total_seats = 0
    if seats.present?
      seats.each do |seat|
        if seat.respond_to?(:capacity) && seat.capacity.present? && seat.capacity.to_i > 0
          total_seats += seat.capacity.to_i
        else
          # If a seat has no capacity, assume 1
          total_seats += 1
        end
      end
    end
    
    Rails.logger.info "CAPACITY: Calculated total capacity: #{total_seats} from #{seats.count} seats"
    return true if total_seats.zero? # No seats available at all
    
    # Ensure both dates are present
    if start_dt.nil?
      Rails.logger.error "CAPACITY: Missing start_dt in exceeds_capacity? check"
      return true # Fail safely if no start date
    end
    
    # If end_dt is nil, calculate it based on standard duration
    unless end_dt
      duration = restaurant.reservation_duration || 60 # Default 60 minutes
      end_dt = start_dt + duration.minutes
      Rails.logger.info "CAPACITY: Calculated missing end_dt as #{end_dt} using #{duration} minute duration"
    end
    
    # Log the parameters we're using
    Rails.logger.info "CAPACITY: Checking seats for #{new_party_size} people from #{start_dt} to #{end_dt} (total capacity: #{total_seats})"
    
    # Build query to find overlapping reservations
    overlapping = restaurant
                    .reservations
                    .where.not(status: %w[canceled finished no_show])
                    
    # Add date/time criteria if both dates are present
    overlapping = overlapping.where("start_time < ? AND end_time > ?", end_dt, start_dt)
    
    # Filter by location_id if provided
    overlapping = overlapping.where(location_id: location_id) if location_id.present?
    
    Rails.logger.info "CAPACITY CHECK: Filtering overlapping reservations by location_id=#{location_id}" if location_id.present?
    
    # Get total seats already booked during this time
    already_booked = overlapping.sum(:party_size)
    Rails.logger.info "CAPACITY: Found #{overlapping.count} overlapping reservations, total seats booked: #{already_booked}"
    
    # Check if this party would exceed capacity
    exceeds = (already_booked + new_party_size) > total_seats
    Rails.logger.info "CAPACITY: #{already_booked} + #{new_party_size} #{exceeds ? '>' : '<='} #{total_seats}, so reservation #{exceeds ? 'EXCEEDS' : 'fits within'} capacity"
    
    exceeds
  end
  
  def reservation_service
    @reservation_service ||= begin
      # Ensure we have a restaurant context
      unless current_restaurant.present?
        Rails.logger.error "TENANT ISOLATION: No restaurant context in reservation_service"
        raise TenantAccessDeniedError, "Restaurant context is required for reservation operations"
      end
      
      service = ReservationService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      Rails.logger.error "TENANT ISOLATION: No restaurant context found in ReservationsController"
      render json: { error: 'Restaurant context is required for reservation operations' }, status: :unprocessable_entity
      return false
    end
    Rails.logger.info "TENANT ISOLATION: Validated restaurant context (id: #{current_restaurant.id})"
    true
  end
end
