# app/controllers/reservations_controller.rb

class ReservationsController < ApplicationController
  # Only staff/admin can do index/show/update/destroy
  # but 'create' is public (no login required).
  before_action :authorize_request, except: [ :create ]

  def index
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    scope = Reservation.where(restaurant_id: current_user.restaurant_id)

    # Date filter...
    if params[:date].present?
      begin
        # Handle both simple string and nested parameter formats
        date_param = params[:date].is_a?(ActionController::Parameters) ? params[:date][:date] : params[:date]
        date_filter = Date.parse(date_param)
        restaurant = Restaurant.find(current_user.restaurant_id)
        tz = restaurant.time_zone.presence || "Pacific/Guam"

        start_local = Time.use_zone(tz) { Time.zone.local(date_filter.year, date_filter.month, date_filter.day, 0, 0, 0) }
        end_local   = start_local.end_of_day

        start_utc = start_local.utc
        end_utc   = end_local.utc
        scope = scope.where("start_time >= ? AND start_time < ?", start_utc, end_utc)
      rescue ArgumentError
        Rails.logger.warn "[ReservationsController#index] invalid date param=#{params[:date]}"
      end
    end

    reservations = scope.all

    render json: reservations.as_json(
      only: [
        :id, :restaurant_id, :start_time, :end_time, :party_size,
        :contact_name, :contact_phone, :contact_email,
        :deposit_amount, :reservation_source, :special_requests,
        :status, :created_at, :updated_at, :duration_minutes,
        :seat_preferences
      ],
      methods: :seat_labels
    )
  end

  def show
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])

    render json: reservation.as_json(
      only: [
        :id, :restaurant_id, :start_time, :end_time, :party_size,
        :contact_name, :contact_phone, :contact_email,
        :deposit_amount, :reservation_source, :special_requests,
        :status, :created_at, :updated_at, :duration_minutes,
        :seat_preferences
      ],
      methods: :seat_labels
    )
  end

  # Public create
  def create
    # ---- DEBUG LOGGING ----
    Rails.logger.debug "DEBUG: raw params = #{params.inspect}"

    # This calls strong params. Let's log what we get back:
    Rails.logger.debug "DEBUG: reservation_params = #{reservation_params.inspect}"

    @reservation = Reservation.new

    # 1) Manually parse start_time from reservation_params
    if reservation_params[:start_time].present?
      parsed_start = Time.zone.parse(reservation_params[:start_time])
      if parsed_start.nil?
        return render json: { error: "Invalid start_time format" }, status: :unprocessable_entity
      end
      @reservation.start_time = parsed_start
    end

    # 2) If an end_time was passed
    if reservation_params[:end_time].present?
      parsed_end = Time.zone.parse(reservation_params[:end_time])
      return render json: { error: "Invalid end_time format" }, status: :unprocessable_entity if parsed_end.nil?
      @reservation.end_time = parsed_end
    else
      # If your model sets end_time automatically based on duration_minutes,
      # you can skip assigning it here.
    end

    # 3) Copy other fields from reservation_params
    @reservation.restaurant_id       = reservation_params[:restaurant_id]
    @reservation.party_size         = reservation_params[:party_size]
    @reservation.contact_name       = reservation_params[:contact_name]
    @reservation.contact_phone      = reservation_params[:contact_phone]
    @reservation.contact_email      = reservation_params[:contact_email]
    @reservation.deposit_amount     = reservation_params[:deposit_amount]
    @reservation.reservation_source = reservation_params[:reservation_source]
    @reservation.special_requests   = reservation_params[:special_requests]
    @reservation.status             = reservation_params[:status]
    @reservation.duration_minutes   = reservation_params[:duration_minutes] if reservation_params[:duration_minutes].present?

    # 4) seat_preferences: need seat_preferences: [[]] in strong parameters
    if reservation_params[:seat_preferences].present?
      Rails.logger.debug "DEBUG: seat_preferences from params = #{reservation_params[:seat_preferences].inspect}"
      @reservation.seat_preferences = reservation_params[:seat_preferences]
    end

    # If staff/admin, force the restaurant_id
    if current_user && current_user.role != "super_admin"
      @reservation.restaurant_id = current_user.restaurant_id
    else
      # If no user or super_admin, default to 1 if not provided
      @reservation.restaurant_id ||= 1
    end

    # Require a valid start_time
    unless @reservation.start_time
      return render json: { error: "start_time is required" }, status: :unprocessable_entity
    end

    # 5) Check capacity
    restaurant = Restaurant.find(@reservation.restaurant_id)
    if exceeds_capacity?(restaurant, @reservation.start_time, @reservation.end_time, @reservation.party_size)
      return render json: { error: "Not enough seats for that timeslot" }, status: :unprocessable_entity
    end

    # ---- DEBUG: see what's in memory right before save
    Rails.logger.debug "DEBUG: about to save. @reservation.seat_preferences = #{@reservation.seat_preferences.inspect}"

    # 6) Save
    if @reservation.save
      # Get notification preferences - only don't send if explicitly set to false
      notification_channels = restaurant.admin_settings&.dig("notification_channels", "reservations") || {}

      # Optionally send a confirmation email - send unless explicitly disabled
      if notification_channels["email"] != false && @reservation.contact_email.present?
        ReservationMailer.booking_confirmation(@reservation).deliver_later
      end

      # Optionally send a text message - send unless explicitly disabled
      if notification_channels["sms"] != false && @reservation.contact_phone.present?
        restaurant_name = restaurant.name
        # Use custom SMS sender ID if set, otherwise use restaurant name
        sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name

        message_body = <<~MSG.squish
          Hi #{@reservation.contact_name}, your #{restaurant_name} reservation is confirmed
          on #{@reservation.start_time.strftime("%B %d at %I:%M %p")}.
          #{@reservation.deposit_amount && @reservation.deposit_amount > 0 ? "Deposit amount: $#{sprintf("%.2f", @reservation.deposit_amount.to_f)}. " : ""}
          We look forward to seeing you!
        MSG
        ClicksendClient.send_text_message(
          to:   @reservation.contact_phone,
          body: message_body,
          from: sms_sender
        )
      end

      render json: @reservation, status: :created
    else
      render json: { errors: @reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])
    if reservation.update(reservation_params)
      render json: reservation, status: :ok
    else
      render json: { errors: reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])
    reservation.destroy
    head :no_content
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
      :duration_minutes
      # Not seat_preferences here
    )

    # Manually insert seat_preferences if present
    if params[:reservation].key?(:seat_preferences)
      allowed[:seat_preferences] = params[:reservation][:seat_preferences]
    end

    allowed
  end

  def exceeds_capacity?(restaurant, start_dt, end_dt, new_party_size)
    total_seats = restaurant.current_seats.count
    return true if total_seats.zero?

    # Overlapping reservations: same restaurant, not canceled/finished/no_show,
    # and time range overlaps
    overlapping = restaurant
                    .reservations
                    .where.not(status: %w[canceled finished no_show])
                    .where("start_time < ? AND end_time > ?", end_dt, start_dt)

    already_booked = overlapping.sum(:party_size)
    (already_booked + new_party_size) > total_seats
  end
end
