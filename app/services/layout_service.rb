# app/services/layout_service.rb
class LayoutService < TenantScopedService
  attr_accessor :current_user

  # List all layouts for the current restaurant
  def list_layouts
    begin
      layouts = scope_query(Layout).all
      { success: true, layouts: layouts }
    rescue => e
      { success: false, errors: ["Failed to fetch layouts: #{e.message}"], status: :internal_server_error }
    end
  end

  # Find a specific layout by ID
  def find_layout(id)
    begin
      layout = scope_query(Layout).find_by(id: id)
      
      if layout.nil?
        return { success: false, errors: ["Layout not found"], status: :not_found }
      end
      
      # Get seat sections with seats
      seat_sections = layout.seat_sections.includes(:seats)
      
      # Get active seat allocations
      seat_allocations = scope_query(SeatAllocation)
        .includes(:reservation, :waitlist_entry)
        .where(seat_id: seat_sections.flat_map(&:seats).pluck(:id), released_at: nil)
      
      # Build occupant map
      occupant_map = {}
      seat_allocations.each do |alloc|
        occupant = alloc.reservation || alloc.waitlist_entry
        occupant_map[alloc.seat_id] = {
          occupant_type: alloc.reservation_id ? "reservation" : "waitlist",
          occupant_name: occupant.contact_name,
          occupant_party_size: occupant.try(:party_size),
          occupant_status: occupant.status
        }
      end
      
      # Build sections data
      rebuilt_sections_data = {
        sections: seat_sections.map do |sec|
          {
            id: sec.id.to_s,
            name: sec.name,
            type: sec.section_type,
            orientation: sec.orientation,
            offsetX: sec.offset_x,
            offsetY: sec.offset_y,
            floorNumber: sec.floor_number,
            seats: sec.seats.map do |seat|
              {
                id: seat.id,
                label: seat.label,
                position_x: seat.position_x,
                position_y: seat.position_y,
                capacity: seat.capacity
              }
            end
          }
        end
      }
      
      # Build complete layout data
      layout_data = {
        id: layout.id,
        name: layout.name,
        sections_data: rebuilt_sections_data,
        seat_sections: seat_sections.map do |sec|
          {
            id: sec.id,
            name: sec.name,
            section_type: sec.section_type,
            offset_x: sec.offset_x,
            offset_y: sec.offset_y,
            orientation: sec.orientation,
            floor_number: sec.floor_number,
            seats: sec.seats.map do |seat|
              occ = occupant_map[seat.id]
              {
                id: seat.id,
                label: seat.label,
                position_x: seat.position_x,
                position_y: seat.position_y,
                capacity: seat.capacity,
                status: occ ? "occupied" : "free",
                occupant_info: occ
              }
            end
          }
        end
      }
      
      { success: true, layout: layout_data }
    rescue => e
      { success: false, errors: ["Failed to fetch layout: #{e.message}"], status: :internal_server_error }
    end
  end

  # Create a new layout
  def create_layout(layout_params)
    begin
      # Determine restaurant ID based on user role
      assigned_restaurant_id = if current_user.role == "super_admin" && layout_params[:restaurant_id].present?
                                layout_params[:restaurant_id]
                              else
                                current_restaurant.id
                              end
      
      # Create the layout
      layout = scope_query(Layout).new(
        name: layout_params[:name],
        restaurant_id: assigned_restaurant_id,
        sections_data: layout_params[:sections_data] || {}
      )
      
      ActiveRecord::Base.transaction do
        if layout.save!
          sections_array = layout_params.dig(:sections_data, :sections) || []
          section_ids_in_use = []
          
          # Process each section
          sections_array.each do |sec_data|
            existing_section_id = sec_data["id"].to_i if sec_data["id"].to_s.match?(/^\d+$/)
            seat_section = existing_section_id && existing_section_id > 0 ?
                           layout.seat_sections.find_by(id: existing_section_id) : nil
            seat_section ||= layout.seat_sections.build
            
            seat_section.name = sec_data["name"]
            seat_section.section_type = sec_data["type"] # "table" or "counter"
            seat_section.orientation = sec_data["orientation"]
            seat_section.offset_x = sec_data["offsetX"]
            seat_section.offset_y = sec_data["offsetY"]
            
            # Always set floor_number if the client sends it
            seat_section.floor_number = sec_data["floorNumber"] if sec_data.key?("floorNumber")
            
            seat_section.save!
            section_ids_in_use << seat_section.id
            
            # Process seats for this section
            seats_array = sec_data["seats"] || []
            seat_ids_in_use = []
            
            seats_array.each do |seat_data|
              existing_seat_id = seat_data["id"].to_i if seat_data["id"].to_s.match?(/^\d+$/)
              seat = existing_seat_id && existing_seat_id > 0 ?
                     seat_section.seats.find_by(id: existing_seat_id) : nil
              seat ||= seat_section.seats.build
              
              seat.label = seat_data["label"]
              seat.position_x = seat_data["position_x"]
              seat.position_y = seat_data["position_y"]
              seat.capacity = seat_data["capacity"] || 1
              seat.save!
              
              seat_ids_in_use << seat.id
            end
            
            # Remove seats that are no longer in use
            seat_section.seats.where.not(id: seat_ids_in_use).destroy_all
          end
          
          # Clean up old sections not in use
          layout.seat_sections.where.not(id: section_ids_in_use).destroy_all
          layout.save!
          
          return { success: true, layout: layout }
        else
          return { success: false, errors: layout.errors.full_messages, status: :unprocessable_entity }
        end
      end
    rescue => e
      Rails.logger.error("Layout creation failed => #{e.message}")
      { success: false, errors: ["Failed to create layout: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Update an existing layout
  def update_layout(id, layout_params)
    begin
      layout = scope_query(Layout).find_by(id: id)
      
      if layout.nil?
        return { success: false, errors: ["Layout not found"], status: :not_found }
      end
      
      # Update restaurant ID if needed
      if current_user.role != "super_admin"
        layout.restaurant_id = restaurant.id
      elsif layout_params[:restaurant_id].present?
        layout.restaurant_id = layout_params[:restaurant_id]
      end
      
      # Update layout attributes
      layout.name = layout_params[:name] if layout_params[:name]
      layout.sections_data = layout_params[:sections_data] if layout_params.key?(:sections_data)
      
      sections_array = layout_params.dig(:sections_data, :sections) || []
      
      ActiveRecord::Base.transaction do
        section_ids_in_use = []
        
        # Process each section
        sections_array.each do |sec_data|
          existing_section_id = sec_data["id"].to_i if sec_data["id"].to_s.match?(/^\d+$/)
          seat_section = existing_section_id && existing_section_id > 0 ?
                         layout.seat_sections.find_by(id: existing_section_id) : nil
          seat_section ||= layout.seat_sections.build
          
          seat_section.name = sec_data["name"]
          seat_section.section_type = sec_data["type"]
          seat_section.orientation = sec_data["orientation"]
          seat_section.offset_x = sec_data["offsetX"]
          seat_section.offset_y = sec_data["offsetY"]
          
          # Always set floor_number if the client sends it
          seat_section.floor_number = sec_data["floorNumber"] if sec_data.key?("floorNumber")
          
          seat_section.save!
          section_ids_in_use << seat_section.id
          
          # Process seats for this section
          seats_array = sec_data["seats"] || []
          seat_ids_in_use = []
          
          seats_array.each do |seat_data|
            existing_seat_id = seat_data["id"].to_i if seat_data["id"].to_s.match?(/^\d+$/)
            seat = existing_seat_id && existing_seat_id > 0 ?
                   seat_section.seats.find_by(id: existing_seat_id) : nil
            seat ||= seat_section.seats.build
            
            seat.label = seat_data["label"]
            seat.position_x = seat_data["position_x"]
            seat.position_y = seat_data["position_y"]
            seat.capacity = seat_data["capacity"] || 1
            seat.save!
            
            seat_ids_in_use << seat.id
          end
          
          # Remove seats that are no longer in use
          seat_section.seats.where.not(id: seat_ids_in_use).destroy_all
        end
        
        # Remove old seat sections not in use
        layout.seat_sections.where.not(id: section_ids_in_use).destroy_all
        layout.save!
      end
      
      { success: true, layout: layout }
    rescue => e
      Rails.logger.error("Error updating layout with seat sections: #{e.message}")
      { success: false, errors: ["Failed to update layout: #{e.message}"], status: :unprocessable_entity }
    end
  end

  # Delete a layout
  def delete_layout(id)
    begin
      layout = scope_query(Layout).find_by(id: id)
      
      if layout.nil?
        return { success: false, errors: ["Layout not found"], status: :not_found }
      end
      
      layout.destroy
      { success: true }
    rescue => e
      { success: false, errors: ["Failed to delete layout: #{e.message}"], status: :internal_server_error }
    end
  end

  # Activate a layout for a restaurant
  def activate_layout(id)
    begin
      layout = scope_query(Layout).find_by(id: id)
      
      if layout.nil?
        return { success: false, errors: ["Layout not found"], status: :not_found }
      end
      
      # Check permissions
      unless current_user.role.in?(%w[admin staff super_admin])
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Check if layout belongs to the user's restaurant
      if layout.restaurant_id != restaurant.id && current_user.role != "super_admin"
        return { success: false, errors: ["Layout does not belong to your restaurant"], status: :forbidden }
      end
      
      # Activate the layout
      layout.restaurant.update!(current_layout_id: layout.id)
      
      { 
        success: true, 
        message: "Layout #{layout.name} (ID #{layout.id}) is now active for Restaurant #{layout.restaurant_id}" 
      }
    rescue => e
      { success: false, errors: ["Failed to activate layout: #{e.message}"], status: :internal_server_error }
    end
  end
end
