# app/services/seat_allocation_service.rb
class SeatAllocationService < TenantScopedService
  attr_accessor :current_user

  # List all seat allocations for the current restaurant
  def list_allocations(filters = {})
    begin
      query = scope_query(SeatAllocation).includes(:seat, :reservation, :waitlist_entry)
      
      # Apply filters
      if filters[:seat_id].present?
        query = query.where(seat_id: filters[:seat_id])
      end
      
      if filters[:reservation_id].present?
        query = query.where(reservation_id: filters[:reservation_id])
      end
      
      if filters[:waitlist_entry_id].present?
        query = query.where(waitlist_entry_id: filters[:waitlist_entry_id])
      end
      
      # Filter by active/inactive status
      if filters[:active].present?
        if ActiveModel::Type::Boolean.new.cast(filters[:active])
          query = query.where(released_at: nil)
        else
          query = query.where.not(released_at: nil)
        end
      end
      
      # Filter by date range
      if filters[:start_date].present? && filters[:end_date].present?
        begin
          start_date = Date.parse(filters[:start_date]).beginning_of_day
          end_date = Date.parse(filters[:end_date]).end_of_day
          query = query.where("start_time BETWEEN ? AND ?", start_date, end_date)
        rescue ArgumentError
          return { 
            success: false, 
            errors: ["Invalid date format. Use YYYY-MM-DD."], 
            status: :unprocessable_entity 
          }
        end
      end
      
      allocations = query.all
      
      { success: true, allocations: allocations }
    rescue => e
      { success: false, errors: ["Failed to fetch seat allocations: #{e.message}"], status: :internal_server_error }
    end
  end

  # Find a specific seat allocation by ID
  def find_allocation(id)
    begin
      allocation = scope_query(SeatAllocation)
        .includes(:seat, :reservation, :waitlist_entry)
        .find_by(id: id)
      
      if allocation.nil?
        return { success: false, errors: ["Seat allocation not found"], status: :not_found }
      end
      
      { success: true, allocation: allocation }
    rescue => e
      { success: false, errors: ["Failed to fetch seat allocation: #{e.message}"], status: :internal_server_error }
    end
  end

  # Create a new seat allocation
  def create_allocation(allocation_params)
    begin
      # Validate seat belongs to current restaurant
      seat_id = allocation_params[:seat_id]
      seat = scope_query(Seat).find_by(id: seat_id)
      
      if seat.nil?
        return { success: false, errors: ["Seat not found"], status: :not_found }
      end
      
      # Check if seat is already allocated
      active_allocation = scope_query(SeatAllocation)
        .where(seat_id: seat.id, released_at: nil)
        .exists?
      
      if active_allocation
        return { 
          success: false, 
          errors: ["Seat is already allocated"], 
          status: :unprocessable_entity 
        }
      end
      
      # Determine what we're allocating to (reservation or waitlist)
      reservation_id = allocation_params[:reservation_id]
      waitlist_entry_id = allocation_params[:waitlist_entry_id]
      
      if reservation_id.present?
        # Validate reservation belongs to current restaurant
        reservation = scope_query(Reservation).find_by(id: reservation_id)
        
        if reservation.nil?
          return { success: false, errors: ["Reservation not found"], status: :not_found }
        end
        
        # Create allocation
        allocation = SeatAllocation.new(
          seat_id: seat.id,
          reservation_id: reservation.id,
          start_time: allocation_params[:start_time] || Time.current
        )
      elsif waitlist_entry_id.present?
        # Validate waitlist entry belongs to current restaurant
        waitlist_entry = scope_query(WaitlistEntry).find_by(id: waitlist_entry_id)
        
        if waitlist_entry.nil?
          return { success: false, errors: ["Waitlist entry not found"], status: :not_found }
        end
        
        # Create allocation
        allocation = SeatAllocation.new(
          seat_id: seat.id,
          waitlist_entry_id: waitlist_entry.id,
          start_time: allocation_params[:start_time] || Time.current
        )
      else
        return { 
          success: false, 
          errors: ["Must provide either reservation_id or waitlist_entry_id"], 
          status: :unprocessable_entity 
        }
      end
      
      if allocation.save
        { success: true, allocation: allocation }
      else
        { success: false, errors: allocation.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create seat allocation: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Update an existing seat allocation
  def update_allocation(id, allocation_params)
    begin
      allocation = scope_query(SeatAllocation).find_by(id: id)
      
      if allocation.nil?
        return { success: false, errors: ["Seat allocation not found"], status: :not_found }
      end
      
      # Only allow updating specific fields
      update_params = {}
      
      # Update released_at if provided
      if allocation_params[:released_at].present?
        update_params[:released_at] = allocation_params[:released_at]
      end
      
      # Update notes if provided
      if allocation_params[:notes].present?
        update_params[:notes] = allocation_params[:notes]
      end
      
      if allocation.update(update_params)
        { success: true, allocation: allocation }
      else
        { success: false, errors: allocation.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update seat allocation: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Delete a seat allocation
  def delete_allocation(id)
    begin
      allocation = scope_query(SeatAllocation).find_by(id: id)
      
      if allocation.nil?
        return { success: false, errors: ["Seat allocation not found"], status: :not_found }
      end
      
      allocation.destroy
      { success: true }
    rescue => e
      { success: false, errors: ["Failed to delete seat allocation: #{e.message}"], status: :internal_server_error }
    end
  end

  # Release a seat allocation
  def release_allocation(id)
    begin
      allocation = scope_query(SeatAllocation).find_by(id: id)
      
      if allocation.nil?
        return { success: false, errors: ["Seat allocation not found"], status: :not_found }
      end
      
      if allocation.released_at.present?
        return { 
          success: false, 
          errors: ["Seat allocation is already released"], 
          status: :unprocessable_entity 
        }
      end
      
      if allocation.update(released_at: Time.current)
        { success: true, allocation: allocation }
      else
        { success: false, errors: allocation.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to release seat allocation: #{e.message}"], status: :internal_server_error }
    end
  end

  # Bulk allocate seats
  def bulk_allocate(bulk_params)
    begin
      seat_ids = bulk_params[:seat_ids]
      reservation_id = bulk_params[:reservation_id]
      waitlist_entry_id = bulk_params[:waitlist_entry_id]
      
      if seat_ids.blank?
        return { 
          success: false, 
          errors: ["Seat IDs are required"], 
          status: :unprocessable_entity 
        }
      end
      
      if reservation_id.blank? && waitlist_entry_id.blank?
        return { 
          success: false, 
          errors: ["Must provide either reservation_id or waitlist_entry_id"], 
          status: :unprocessable_entity 
        }
      end
      
      # Validate seats belong to current restaurant
      seats = scope_query(Seat).where(id: seat_ids)
      
      if seats.count != seat_ids.count
        return { 
          success: false, 
          errors: ["One or more seats not found"], 
          status: :not_found 
        }
      end
      
      # Check if any seats are already allocated
      already_allocated = scope_query(SeatAllocation)
        .where(seat_id: seat_ids, released_at: nil)
        .exists?
      
      if already_allocated
        return { 
          success: false, 
          errors: ["One or more seats are already allocated"], 
          status: :unprocessable_entity 
        }
      end
      
      allocations = []
      
      ActiveRecord::Base.transaction do
        if reservation_id.present?
          # Validate reservation belongs to current restaurant
          reservation = scope_query(Reservation).find_by(id: reservation_id)
          
          if reservation.nil?
            raise ActiveRecord::Rollback
            return { success: false, errors: ["Reservation not found"], status: :not_found }
          end
          
          # Create allocations
          seat_ids.each do |seat_id|
            allocation = SeatAllocation.create!(
              seat_id: seat_id,
              reservation_id: reservation.id,
              start_time: bulk_params[:start_time] || Time.current
            )
            allocations << allocation
          end
        elsif waitlist_entry_id.present?
          # Validate waitlist entry belongs to current restaurant
          waitlist_entry = scope_query(WaitlistEntry).find_by(id: waitlist_entry_id)
          
          if waitlist_entry.nil?
            raise ActiveRecord::Rollback
            return { success: false, errors: ["Waitlist entry not found"], status: :not_found }
          end
          
          # Create allocations
          seat_ids.each do |seat_id|
            allocation = SeatAllocation.create!(
              seat_id: seat_id,
              waitlist_entry_id: waitlist_entry.id,
              start_time: bulk_params[:start_time] || Time.current
            )
            allocations << allocation
          end
        end
      end
      
      { success: true, allocations: allocations }
    rescue => e
      { success: false, errors: ["Failed to bulk allocate seats: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Bulk release seats
  def bulk_release(seat_ids)
    begin
      if seat_ids.blank?
        return { 
          success: false, 
          errors: ["Seat IDs are required"], 
          status: :unprocessable_entity 
        }
      end
      
      # Find active allocations for these seats
      allocations = scope_query(SeatAllocation)
        .where(seat_id: seat_ids, released_at: nil)
      
      if allocations.empty?
        return { 
          success: false, 
          errors: ["No active allocations found for these seats"], 
          status: :not_found 
        }
      end
      
      # Release all allocations
      ActiveRecord::Base.transaction do
        allocations.each do |allocation|
          allocation.update!(released_at: Time.current)
        end
      end
      
      { success: true, allocations: allocations }
    rescue => e
      { success: false, errors: ["Failed to bulk release seats: #{e.message}"], status: :internal_server_error }
    end
  end
end
