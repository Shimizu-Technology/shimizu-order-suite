# app/services/seat_section_service.rb
class SeatSectionService < TenantScopedService
  attr_accessor :current_user

  # List all seat sections for the current restaurant
  def list_seat_sections(layout_id = nil)
    begin
      query = scope_query(SeatSection).includes(:seats)
      
      # Filter by layout if provided
      if layout_id.present?
        layout = scope_query(Layout).find_by(id: layout_id)
        
        if layout.nil?
          return { success: false, errors: ["Layout not found"], status: :not_found }
        end
        
        query = query.where(layout_id: layout.id)
      end
      
      seat_sections = query.all
      
      { success: true, seat_sections: seat_sections }
    rescue => e
      { success: false, errors: ["Failed to fetch seat sections: #{e.message}"], status: :internal_server_error }
    end
  end

  # Find a specific seat section by ID
  def find_seat_section(id)
    begin
      seat_section = scope_query(SeatSection).includes(:seats).find_by(id: id)
      
      if seat_section.nil?
        return { success: false, errors: ["Seat section not found"], status: :not_found }
      end
      
      { success: true, seat_section: seat_section }
    rescue => e
      { success: false, errors: ["Failed to fetch seat section: #{e.message}"], status: :internal_server_error }
    end
  end

  # Create a new seat section
  def create_seat_section(section_params)
    begin
      # Validate layout belongs to current restaurant
      layout_id = section_params[:layout_id]
      layout = scope_query(Layout).find_by(id: layout_id)
      
      if layout.nil?
        return { success: false, errors: ["Layout not found"], status: :not_found }
      end
      
      # Create the seat section
      seat_section = layout.seat_sections.build(
        name: section_params[:name],
        section_type: section_params[:section_type],
        orientation: section_params[:orientation],
        offset_x: section_params[:offset_x],
        offset_y: section_params[:offset_y],
        floor_number: section_params[:floor_number] || 1
      )
      
      if seat_section.save
        # Create seats if provided
        if section_params[:seats].present?
          section_params[:seats].each do |seat_data|
            seat = seat_section.seats.build(
              label: seat_data[:label],
              position_x: seat_data[:position_x],
              position_y: seat_data[:position_y],
              capacity: seat_data[:capacity] || 1
            )
            seat.save
          end
        end
        
        { success: true, seat_section: seat_section }
      else
        { success: false, errors: seat_section.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create seat section: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Update an existing seat section
  def update_seat_section(id, section_params)
    begin
      seat_section = scope_query(SeatSection).find_by(id: id)
      
      if seat_section.nil?
        return { success: false, errors: ["Seat section not found"], status: :not_found }
      end
      
      # If layout_id is being changed, validate the new layout belongs to current restaurant
      if section_params[:layout_id].present? && section_params[:layout_id] != seat_section.layout_id
        new_layout = scope_query(Layout).find_by(id: section_params[:layout_id])
        
        if new_layout.nil?
          return { success: false, errors: ["New layout not found"], status: :not_found }
        end
      end
      
      # Update the seat section
      if seat_section.update(section_params.except(:seats))
        # Update seats if provided
        if section_params[:seats].present?
          seat_ids_in_use = []
          
          section_params[:seats].each do |seat_data|
            if seat_data[:id].present?
              # Update existing seat
              seat = seat_section.seats.find_by(id: seat_data[:id])
              
              if seat.present?
                seat.update(
                  label: seat_data[:label],
                  position_x: seat_data[:position_x],
                  position_y: seat_data[:position_y],
                  capacity: seat_data[:capacity] || 1
                )
                seat_ids_in_use << seat.id
              end
            else
              # Create new seat
              seat = seat_section.seats.create(
                label: seat_data[:label],
                position_x: seat_data[:position_x],
                position_y: seat_data[:position_y],
                capacity: seat_data[:capacity] || 1
              )
              seat_ids_in_use << seat.id
            end
          end
          
          # Remove seats that are no longer in use
          seat_section.seats.where.not(id: seat_ids_in_use).destroy_all
        end
        
        { success: true, seat_section: seat_section }
      else
        { success: false, errors: seat_section.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update seat section: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Delete a seat section
  def delete_seat_section(id)
    begin
      seat_section = scope_query(SeatSection).find_by(id: id)
      
      if seat_section.nil?
        return { success: false, errors: ["Seat section not found"], status: :not_found }
      end
      
      # Check if there are any active seat allocations
      active_allocations = scope_query(SeatAllocation)
        .where(seat_id: seat_section.seats.pluck(:id), released_at: nil)
        .exists?
      
      if active_allocations
        return { 
          success: false, 
          errors: ["Cannot delete section with active seat allocations"], 
          status: :unprocessable_entity 
        }
      end
      
      seat_section.destroy
      { success: true }
    rescue => e
      { success: false, errors: ["Failed to delete seat section: #{e.message}"], status: :internal_server_error }
    end
  end
end
