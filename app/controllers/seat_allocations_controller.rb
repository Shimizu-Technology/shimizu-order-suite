# app/controllers/seat_allocations_controller.rb

class SeatAllocationsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  # GET /seat_allocations?date=YYYY-MM-DD
  def index
    Rails.logger.debug "[SeatAllocationsController#index] params=#{params.inspect}"

    filters = {}
    filters[:active] = true # Only get active (unreleased) allocations by default
    
    if params[:date].present?
      begin
        # Handle both simple string and nested parameter formats
        date_param = params[:date].is_a?(ActionController::Parameters) ? params[:date][:date] : params[:date]
        filters[:start_date] = date_param
        filters[:end_date] = date_param
      rescue ArgumentError
        Rails.logger.warn "[SeatAllocationsController#index] invalid date param=#{params[:date]}"
        return render json: { error: "Invalid date format" }, status: :unprocessable_entity
      end
    end
    
    # Add any other filters from params
    filters[:seat_id] = params[:seat_id] if params[:seat_id].present?
    filters[:reservation_id] = params[:reservation_id] if params[:reservation_id].present?
    filters[:waitlist_entry_id] = params[:waitlist_entry_id] if params[:waitlist_entry_id].present?
    
    result = seat_allocation_service.list_allocations(filters)
    
    if result[:success]
      # Format the allocations for the response
      formatted_allocations = result[:allocations].map do |alloc|
        occupant_type = if alloc.reservation_id.present?
                          "reservation"
        elsif alloc.waitlist_entry_id.present?
                          "waitlist"
        end

        occupant_id         = nil
        occupant_name       = nil
        occupant_party_size = nil
        occupant_status     = nil

        if occupant_type == "reservation" && alloc.reservation
          occupant_id         = alloc.reservation.id
          occupant_name       = alloc.reservation.contact_name
          occupant_party_size = alloc.reservation.party_size
          occupant_status     = alloc.reservation.status
        elsif occupant_type == "waitlist" && alloc.waitlist_entry
          occupant_id         = alloc.waitlist_entry.id
          occupant_name       = alloc.waitlist_entry.contact_name
          occupant_party_size = alloc.waitlist_entry.party_size
          occupant_status     = alloc.waitlist_entry.status
        end

        {
          id:                  alloc.id,
          seat_id:             alloc.seat_id,
          seat_label:          alloc.seat&.label,
          occupant_type:       occupant_type,
          occupant_id:         occupant_id,
          occupant_name:       occupant_name,
          occupant_party_size: occupant_party_size,
          occupant_status:     occupant_status,
          start_time:          alloc.start_time,
          end_time:            alloc.released_at,
          released_at:         alloc.released_at
        }
      end
      
      render json: formatted_allocations
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  # POST /seat_allocations/multi_create
  def multi_create
    sa_params = params.require(:seat_allocation).permit(:occupant_type, :occupant_id, :start_time, :end_time, seat_ids: [])

    occupant_type = sa_params[:occupant_type]
    occupant_id   = sa_params[:occupant_id]
    seat_ids      = sa_params[:seat_ids] || []
    
    # Prepare bulk allocation parameters
    bulk_params = {
      seat_ids: seat_ids,
      start_time: parse_time(sa_params[:start_time]) || Time.current
    }
    
    # Set the appropriate occupant ID based on type
    if occupant_type == "reservation"
      bulk_params[:reservation_id] = occupant_id
    elsif occupant_type == "waitlist"
      bulk_params[:waitlist_entry_id] = occupant_id
    else
      return render json: { error: "Invalid occupant_type. Must be 'reservation' or 'waitlist'" }, status: :unprocessable_entity
    end
    
    # Call the service to perform the bulk allocation
    result = seat_allocation_service.bulk_allocate(bulk_params)
    
    if result[:success]
      # Update the occupant status to "seated"
      if occupant_type == "reservation"
        reservation = scope_query(Reservation).find_by(id: occupant_id)
        if reservation && !%w[seated finished canceled no_show removed].include?(reservation.status)
          reservation.update(status: "seated")
        end
      elsif occupant_type == "waitlist"
        waitlist_entry = scope_query(WaitlistEntry).find_by(id: occupant_id)
        if waitlist_entry && !%w[seated finished canceled no_show removed].include?(waitlist_entry.status)
          waitlist_entry.update(status: "seated")
        end
      end
      
      start_time = result[:allocations].first&.start_time || Time.current
      msg = "Seats allocated (seated) from #{start_time.strftime('%H:%M')} for occupant #{occupant_id}"
      render json: { message: msg, allocations: result[:allocations] }, status: :created
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /seat_allocations/reserve
  def reserve
    ra_params = params.require(:seat_allocation).permit(:occupant_type, :occupant_id, :start_time, :end_time, seat_ids: [], seat_labels: [])

    occupant_type = ra_params[:occupant_type]
    occupant_id   = ra_params[:occupant_id]
    seat_ids      = ra_params[:seat_ids] || []
    seat_labels   = ra_params[:seat_labels] || []

    # Convert seat_labels -> seat_ids if seat_ids is empty
    if seat_ids.empty? && seat_labels.any?
      seat_ids = scope_query(Seat).where(label: seat_labels).pluck(:id)
    end

    if occupant_type.blank? || occupant_id.blank? || seat_ids.empty?
      return render json: { error: "Must provide occupant_type, occupant_id, and at least one seat" }, status: :unprocessable_entity
    end
    
    # Prepare bulk allocation parameters
    bulk_params = {
      seat_ids: seat_ids,
      start_time: parse_time(ra_params[:start_time]) || Time.current
    }
    
    # Set the appropriate occupant ID based on type
    if occupant_type == "reservation"
      bulk_params[:reservation_id] = occupant_id
    elsif occupant_type == "waitlist"
      bulk_params[:waitlist_entry_id] = occupant_id
    else
      return render json: { error: "Invalid occupant_type. Must be 'reservation' or 'waitlist'" }, status: :unprocessable_entity
    end
    
    # Call the service to perform the bulk allocation
    result = seat_allocation_service.bulk_allocate(bulk_params)
    
    if result[:success]
      # Update the occupant status to "reserved"
      if occupant_type == "reservation"
        reservation = scope_query(Reservation).find_by(id: occupant_id)
        if reservation && !%w[seated finished canceled no_show removed].include?(reservation.status)
          reservation.update(status: "reserved")
        end
      elsif occupant_type == "waitlist"
        waitlist_entry = scope_query(WaitlistEntry).find_by(id: occupant_id)
        if waitlist_entry && !%w[seated finished canceled no_show removed].include?(waitlist_entry.status)
          waitlist_entry.update(status: "reserved")
        end
      end
      
      start_time = result[:allocations].first&.start_time || Time.current
      msg = "Seats reserved from #{start_time.strftime('%H:%M')}."
      render json: { message: msg, allocations: result[:allocations] }, status: :created
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /seat_allocations/arrive
  def arrive
    Rails.logger.debug "[arrive] params=#{params.inspect}"
    occ_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = occ_params[:occupant_type]
    occupant_id   = occ_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end
    
    # Verify the occupant exists and belongs to this restaurant
    if occupant_type == "reservation"
      occupant = scope_query(Reservation).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Reservation not found" }, status: :not_found
      end
      
      # Validate status
      unless %w[reserved booked].include?(occupant.status)
        return render json: { error: "Reservation is not in reserved/booked status" }, status: :unprocessable_entity
      end
      
      # Update status
      if occupant.update(status: "seated")
        render json: { message: "Arrived => occupant is now 'seated'" }, status: :ok
      else
        render json: { error: "Failed to update reservation status" }, status: :unprocessable_entity
      end
    elsif occupant_type == "waitlist"
      occupant = scope_query(WaitlistEntry).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Waitlist entry not found" }, status: :not_found
      end
      
      # Validate status
      unless %w[waiting reserved].include?(occupant.status)
        return render json: { error: "Waitlist entry is not in waiting/reserved status" }, status: :unprocessable_entity
      end
      
      # Update status
      if occupant.update(status: "seated")
        render json: { message: "Arrived => occupant is now 'seated'" }, status: :ok
      else
        render json: { error: "Failed to update waitlist entry status" }, status: :unprocessable_entity
      end
    else
      render json: { error: "Invalid occupant_type. Must be 'reservation' or 'waitlist'" }, status: :unprocessable_entity
    end
  end

  # POST /seat_allocations/no_show
  def no_show
    ns_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = ns_params[:occupant_type]
    occupant_id   = ns_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end
    
    # Verify the occupant exists and belongs to this restaurant
    if occupant_type == "reservation"
      occupant = scope_query(Reservation).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Reservation not found" }, status: :not_found
      end
    elsif occupant_type == "waitlist"
      occupant = scope_query(WaitlistEntry).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Waitlist entry not found" }, status: :not_found
      end
    else
      return render json: { error: "Invalid occupant_type. Must be 'reservation' or 'waitlist'" }, status: :unprocessable_entity
    end
    
    # Find all active allocations for this occupant
    filters = {}
    filters["#{occupant_type}_id".to_sym] = occupant_id
    filters[:active] = true
    
    # Get the seat IDs for these allocations
    allocations_result = seat_allocation_service.list_allocations(filters)
    
    if !allocations_result[:success]
      return render json: { error: allocations_result[:errors].join(", ") }, status: allocations_result[:status] || :internal_server_error
    end
    
    seat_ids = allocations_result[:allocations].map(&:seat_id)
    
    if seat_ids.empty?
      # If no active allocations, just update the occupant status
      if occupant.update(status: "no_show")
        render json: { message: "Marked occupant as no_show" }, status: :ok
      else
        render json: { error: "Failed to update occupant status" }, status: :unprocessable_entity
      end
    else
      # Release all active allocations
      release_result = seat_allocation_service.bulk_release(seat_ids)
      
      if release_result[:success]
        # Update occupant status
        if occupant.update(status: "no_show")
          render json: { message: "Marked occupant as no_show; seat_allocations released" }, status: :ok
        else
          render json: { error: "Failed to update occupant status" }, status: :unprocessable_entity
        end
      else
        render json: { error: release_result[:errors].join(", ") }, status: release_result[:status] || :internal_server_error
      end
    end
  end

  # POST /seat_allocations/cancel
  def cancel
    c_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = c_params[:occupant_type]
    occupant_id   = c_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end
    
    # Verify the occupant exists and belongs to this restaurant
    if occupant_type == "reservation"
      occupant = scope_query(Reservation).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Reservation not found" }, status: :not_found
      end
    elsif occupant_type == "waitlist"
      occupant = scope_query(WaitlistEntry).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Waitlist entry not found" }, status: :not_found
      end
    else
      return render json: { error: "Invalid occupant_type. Must be 'reservation' or 'waitlist'" }, status: :unprocessable_entity
    end
    
    # Find all active allocations for this occupant
    filters = {}
    filters["#{occupant_type}_id".to_sym] = occupant_id
    filters[:active] = true
    
    # Get the seat IDs for these allocations
    allocations_result = seat_allocation_service.list_allocations(filters)
    
    if !allocations_result[:success]
      return render json: { error: allocations_result[:errors].join(", ") }, status: allocations_result[:status] || :internal_server_error
    end
    
    seat_ids = allocations_result[:allocations].map(&:seat_id)
    
    if seat_ids.empty?
      # If no active allocations, just update the occupant status
      if occupant.update(status: "canceled")
        render json: { message: "Canceled occupant" }, status: :ok
      else
        render json: { error: "Failed to update occupant status" }, status: :unprocessable_entity
      end
    else
      # Release all active allocations
      release_result = seat_allocation_service.bulk_release(seat_ids)
      
      if release_result[:success]
        # Update occupant status
        if occupant.update(status: "canceled")
          render json: { message: "Canceled occupant & freed seats" }, status: :ok
        else
          render json: { error: "Failed to update occupant status" }, status: :unprocessable_entity
        end
      else
        render json: { error: release_result[:errors].join(", ") }, status: release_result[:status] || :internal_server_error
      end
    end
  end

  # DELETE /seat_allocations/:id
  def destroy
    result = seat_allocation_service.release_allocation(params[:id])
    
    if result[:success]
      # Check if this was the last active allocation for the occupant
      allocation = result[:allocation]
      
      if allocation.reservation_id.present?
        # Check for any remaining active allocations for this reservation
        filters = {
          reservation_id: allocation.reservation_id,
          active: true
        }
        
        remaining_allocations = seat_allocation_service.list_allocations(filters)
        
        if remaining_allocations[:success] && remaining_allocations[:allocations].empty?
          # This was the last allocation, update reservation status to finished
          reservation = scope_query(Reservation).find_by(id: allocation.reservation_id)
          reservation&.update(status: "finished")
        end
      elsif allocation.waitlist_entry_id.present?
        # Check for any remaining active allocations for this waitlist entry
        filters = {
          waitlist_entry_id: allocation.waitlist_entry_id,
          active: true
        }
        
        remaining_allocations = seat_allocation_service.list_allocations(filters)
        
        if remaining_allocations[:success] && remaining_allocations[:allocations].empty?
          # This was the last allocation, update waitlist entry status to removed
          waitlist_entry = scope_query(WaitlistEntry).find_by(id: allocation.waitlist_entry_id)
          waitlist_entry&.update(status: "removed")
        end
      end
      
      head :no_content
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /seat_allocations/finish
  def finish
    f_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = f_params[:occupant_type]
    occupant_id   = f_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" },
                    status: :unprocessable_entity
    end
    
    # Verify the occupant exists and belongs to this restaurant
    if occupant_type == "reservation"
      occupant = scope_query(Reservation).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Reservation not found" }, status: :not_found
      end
      new_status = "finished"
    elsif occupant_type == "waitlist"
      occupant = scope_query(WaitlistEntry).find_by(id: occupant_id)
      if occupant.nil?
        return render json: { error: "Waitlist entry not found" }, status: :not_found
      end
      new_status = "removed"
    else
      return render json: { error: "Invalid occupant_type. Must be 'reservation' or 'waitlist'" }, status: :unprocessable_entity
    end
    
    # Find all active allocations for this occupant
    filters = {}
    filters["#{occupant_type}_id".to_sym] = occupant_id
    filters[:active] = true
    
    # Get the seat IDs for these allocations
    allocations_result = seat_allocation_service.list_allocations(filters)
    
    if !allocations_result[:success]
      return render json: { error: allocations_result[:errors].join(", ") }, status: allocations_result[:status] || :internal_server_error
    end
    
    seat_ids = allocations_result[:allocations].map(&:seat_id)
    
    if seat_ids.empty?
      # If no active allocations, just update the occupant status
      if occupant.update(status: new_status)
        render json: { message: "Occupant => #{occupant.status}" }, status: :ok
      else
        render json: { error: "Failed to update occupant status" }, status: :unprocessable_entity
      end
    else
      # Release all active allocations
      release_result = seat_allocation_service.bulk_release(seat_ids)
      
      if release_result[:success]
        # Update occupant status
        if occupant.update(status: new_status)
          render json: { message: "Occupant => #{occupant.status}; seats freed" }, status: :ok
        else
          render json: { error: "Failed to update occupant status" }, status: :unprocessable_entity
        end
      else
        render json: { error: release_result[:errors].join(", ") }, status: release_result[:status] || :internal_server_error
      end
    end
  end

  private

  def parse_time(time_str)
    return nil unless time_str.present?
    Time.zone.parse(time_str) rescue nil
  end
  
  # Helper method to scope queries to the current restaurant
  def scope_query(model_class)
    model_class.where(restaurant_id: current_restaurant.id)
  end
  
  # Get the seat allocation service instance
  def seat_allocation_service
    @seat_allocation_service ||= begin
      service = SeatAllocationService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  # Ensure we have a tenant context
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
