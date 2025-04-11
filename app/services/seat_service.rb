# app/services/seat_service.rb
class SeatService < TenantScopedService
  attr_accessor :current_user

  # List all seats for the current restaurant
  def list_seats(section_id = nil)
    begin
      query = scope_query(Seat)
      
      # Filter by section if provided
      if section_id.present?
        # Verify the section belongs to the current restaurant
        section = scope_query(SeatSection).find_by(id: section_id)
        
        if section.nil?
          return { success: false, errors: ["Seat section not found"], status: :not_found }
        end
        
        query = query.where(seat_section_id: section.id)
      end
      
      seats = query.all
      
      { success: true, seats: seats }
    rescue => e
      { success: false, errors: ["Failed to fetch seats: #{e.message}"], status: :internal_server_error }
    end
  end

  # Find a specific seat by ID
  def find_seat(id)
    begin
      seat = scope_query(Seat).find_by(id: id)
      
      if seat.nil?
        return { success: false, errors: ["Seat not found"], status: :not_found }
      end
      
      # Get current allocation status if any
      allocation = scope_query(SeatAllocation)
        .includes(:reservation, :waitlist_entry)
        .where(seat_id: seat.id, released_at: nil)
        .first
      
      seat_data = seat.as_json
      
      if allocation.present?
        occupant = allocation.reservation || allocation.waitlist_entry
        seat_data[:status] = "occupied"
        seat_data[:occupant_info] = {
          occupant_type: allocation.reservation_id ? "reservation" : "waitlist",
          occupant_name: occupant.contact_name,
          occupant_party_size: occupant.try(:party_size),
          occupant_status: occupant.status
        }
      else
        seat_data[:status] = "free"
      end
      
      { success: true, seat: seat_data }
    rescue => e
      { success: false, errors: ["Failed to fetch seat: #{e.message}"], status: :internal_server_error }
    end
  end

  # Create a new seat
  def create_seat(seat_params)
    begin
      # Validate section belongs to current restaurant
      section_id = seat_params[:seat_section_id]
      section = scope_query(SeatSection).find_by(id: section_id)
      
      if section.nil?
        return { success: false, errors: ["Seat section not found"], status: :not_found }
      end
      
      # Create the seat
      seat = section.seats.build(
        label: seat_params[:label],
        position_x: seat_params[:position_x],
        position_y: seat_params[:position_y],
        capacity: seat_params[:capacity] || 1
      )
      
      if seat.save
        { success: true, seat: seat }
      else
        { success: false, errors: seat.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create seat: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Update an existing seat
  def update_seat(id, seat_params)
    begin
      seat = scope_query(Seat).find_by(id: id)
      
      if seat.nil?
        return { success: false, errors: ["Seat not found"], status: :not_found }
      end
      
      # If section_id is being changed, validate the new section belongs to current restaurant
      if seat_params[:seat_section_id].present? && seat_params[:seat_section_id] != seat.seat_section_id
        new_section = scope_query(SeatSection).find_by(id: seat_params[:seat_section_id])
        
        if new_section.nil?
          return { success: false, errors: ["New seat section not found"], status: :not_found }
        end
      end
      
      # Update the seat
      if seat.update(seat_params)
        { success: true, seat: seat }
      else
        { success: false, errors: seat.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update seat: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Delete a seat
  def delete_seat(id)
    begin
      seat = scope_query(Seat).find_by(id: id)
      
      if seat.nil?
        return { success: false, errors: ["Seat not found"], status: :not_found }
      end
      
      # Check if there are any active allocations
      active_allocation = scope_query(SeatAllocation)
        .where(seat_id: seat.id, released_at: nil)
        .exists?
      
      if active_allocation
        return { 
          success: false, 
          errors: ["Cannot delete seat with active allocation"], 
          status: :unprocessable_entity 
        }
      end
      
      seat.destroy
      { success: true }
    rescue => e
      { success: false, errors: ["Failed to delete seat: #{e.message}"], status: :internal_server_error }
    end
  end

  # Allocate a seat to a reservation or waitlist entry
  def allocate_seat(id, allocation_params)
    begin
      seat = scope_query(Seat).find_by(id: id)
      
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
        allocation = SeatAllocation.create!(
          seat_id: seat.id,
          reservation_id: reservation.id,
          allocated_at: Time.current
        )
      elsif waitlist_entry_id.present?
        # Validate waitlist entry belongs to current restaurant
        waitlist_entry = scope_query(WaitlistEntry).find_by(id: waitlist_entry_id)
        
        if waitlist_entry.nil?
          return { success: false, errors: ["Waitlist entry not found"], status: :not_found }
        end
        
        # Create allocation
        allocation = SeatAllocation.create!(
          seat_id: seat.id,
          waitlist_entry_id: waitlist_entry.id,
          allocated_at: Time.current
        )
      else
        return { 
          success: false, 
          errors: ["Must provide either reservation_id or waitlist_entry_id"], 
          status: :unprocessable_entity 
        }
      end
      
      { success: true, allocation: allocation }
    rescue => e
      { success: false, errors: ["Failed to allocate seat: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Release a seat allocation
  def release_seat(id)
    begin
      seat = scope_query(Seat).find_by(id: id)
      
      if seat.nil?
        return { success: false, errors: ["Seat not found"], status: :not_found }
      end
      
      # Find active allocation
      allocation = scope_query(SeatAllocation)
        .where(seat_id: seat.id, released_at: nil)
        .first
      
      if allocation.nil?
        return { 
          success: false, 
          errors: ["Seat is not currently allocated"], 
          status: :unprocessable_entity 
        }
      end
      
      # Release the allocation
      allocation.update!(released_at: Time.current)
      
      { success: true }
    rescue => e
      { success: false, errors: ["Failed to release seat: #{e.message}"], status: :internal_server_error }
    end
  end
end
