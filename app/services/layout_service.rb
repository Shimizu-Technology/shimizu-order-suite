# app/services/layout_service.rb
class LayoutService < TenantScopedService
  attr_accessor :current_user

  # List all layouts for the current restaurant, optionally filtered by location
  def list_layouts(location_id = nil)
    begin
      # Start with all layouts for the current restaurant
      layouts_query = scope_query(Layout)
      
      # Filter by location if provided
      layouts_query = layouts_query.where(location_id: location_id) if location_id.present?
      
      # Get all matching layouts
      layouts = layouts_query.all
      
      # Get the current active layout ID from the restaurant
      restaurant_current_layout_id = restaurant.current_layout_id
      
      # Get current location if specified
      current_location = location_id.present? ? Location.find_by(id: location_id) : nil
      location_current_layout_id = current_location&.current_layout_id
      
      # Transform layouts to include is_active flag
      enriched_layouts = layouts.map do |layout|
        layout_hash = layout.as_json
        
        # Determine if the layout is active based on both restaurant and location context
        if layout.location_id.present?
          # For layouts with a location_id, check if it's active for that location
          layout_location = layout.location_id == location_id ? current_location : Location.find_by(id: layout.location_id)
          layout_hash['is_active'] = (layout.id == layout_location&.current_layout_id)
        else
          # For layouts without a location_id (global layouts), check against restaurant
          layout_hash['is_active'] = (layout.id == restaurant_current_layout_id)
        end
        
        layout_hash
      end
      
      { success: true, layouts: enriched_layouts }
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
      
      # First extract shape data from the JSON sections
      json_section_map = {}
      
      if layout.sections_data && layout.sections_data["sections"].is_a?(Array)
        layout.sections_data["sections"].each do |json_section|
          section_id = json_section["id"].to_s
          section_database_id = json_section["database_id"].to_s if json_section["database_id"]
          
          # Store by both original ID and database ID if they differ
          json_section_map[section_id] = json_section
          json_section_map[section_database_id] = json_section if section_database_id && section_database_id != section_id
        end
      end
      
      # Build sections data
      rebuilt_sections_data = {
        sections: seat_sections.map do |sec|
          section_id = sec.id.to_s
          json_section = json_section_map[section_id]
          
          # Create the base section
          section_data = {
            id: section_id,
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
          
          # Add shape, dimensions, and rotation from the original JSON if available
          if json_section
            section_data[:shape] = json_section["shape"] if json_section["shape"]
            section_data[:dimensions] = json_section["dimensions"] if json_section["dimensions"]
            section_data[:rotation] = json_section["rotation"] if json_section["rotation"]
          end
          
          section_data
        end
      }
      
      # Check if this is the active layout for the restaurant/location
      if layout.location_id.present?
        # For layouts with a location_id, check if it's active for that location
        location = Location.find_by(id: layout.location_id)
        is_active = (layout.id == location&.current_layout_id)
      else
        # For layouts without a location_id (global layouts), check against restaurant
        is_active = (layout.id == restaurant.current_layout_id)
      end

      # Get shape data from sections_data JSON for each section
      shape_data_map = {}
      name_to_shape_map = {}
      if layout.sections_data && layout.sections_data["sections"].is_a?(Array)
        layout.sections_data["sections"].each do |json_section|
          # Try to match section by ID - can be string or integer
          section_id = json_section["id"].to_s
          section_name = json_section["name"].to_s
          
          # Debug
          Rails.logger.debug("JSON section ID: #{section_id}, name: #{section_name}, shape: #{json_section['shape']}")
          
          # Store shape data keyed by both ID and name for redundancy
          shape_data = {
            shape: json_section["shape"],
            dimensions: json_section["dimensions"],
            rotation: json_section["rotation"]
          }
          
          # Map by ID
          shape_data_map[section_id] = shape_data
          
          # Also map by name as fallback
          name_to_shape_map[section_name] = shape_data if section_name.present?
        end
      end
      
      # Build complete layout data
      layout_data = {
        id: layout.id,
        name: layout.name,
        is_active: is_active,
        sections_data: rebuilt_sections_data,
        seat_sections: seat_sections.map do |sec|
          # First try to match by ID
          section_shape_data = shape_data_map[sec.id.to_s] || {}
          
          # If no shape data found by ID, try to match by name as fallback
          if section_shape_data.empty? && sec.name.present? && name_to_shape_map[sec.name]
            section_shape_data = name_to_shape_map[sec.name]
            Rails.logger.debug("Section ID #{sec.id} not matched directly, but matched by name '#{sec.name}'")
          end
          
          # Debug
          Rails.logger.debug("Section ID: #{sec.id}, Name: #{sec.name}, Found shape data: #{section_shape_data}")
          
          {
            id: sec.id,
            name: sec.name,
            section_type: sec.section_type,
            offset_x: sec.offset_x,
            offset_y: sec.offset_y,
            orientation: sec.orientation,
            floor_number: sec.floor_number,
            # Important: Include shape data from JSON
            shape: section_shape_data[:shape],
            dimensions: section_shape_data[:dimensions],
            rotation: section_shape_data[:rotation],
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
                                 @restaurant.id
                               end
      
      # Determine location ID (use default location if not specified)
      assigned_location_id = if layout_params[:location_id].present?
                             layout_params[:location_id]
                           else
                             # Find default location for the restaurant
                             default_location = Location.find_by(restaurant_id: assigned_restaurant_id, is_default: true)
                             default_location&.id
                           end

      # Create the layout
      layout = scope_query(Layout).new(
        name: layout_params[:name],
        restaurant_id: assigned_restaurant_id,
        location_id: assigned_location_id,
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
        layout.restaurant_id = @restaurant.id
      elsif layout_params[:restaurant_id].present?
        layout.restaurant_id = layout_params[:restaurant_id]
      end
      
      # Update location if provided
      if layout_params[:location_id].present?
        layout.location_id = layout_params[:location_id]
      end

      # Update layout attributes
      layout.name = layout_params[:name] if layout_params[:name]
      layout.sections_data = layout_params[:sections_data] if layout_params.key?(:sections_data)
      
      sections_array = layout_params.dig(:sections_data, :sections) || []
      
      ActiveRecord::Base.transaction do
        section_ids_in_use = []
        
        # Keep track of ID mappings from temp IDs to database IDs
        orig_id_to_db_id_map = {}
        
        # Process each section
        sections_array.each do |sec_data|
          # Store the original ID (could be temporary ID like 'section-123456')
          original_id = sec_data["id"]
          
          # Try to extract numeric ID for database lookup
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
          
          # Store shape data in additional metadata for reference (won't be saved in DB directly)
          seat_section.instance_variable_set("@shape", sec_data["shape"]) if sec_data["shape"]
          seat_section.instance_variable_set("@dimensions", sec_data["dimensions"]) if sec_data["dimensions"]
          seat_section.instance_variable_set("@rotation", sec_data["rotation"]) if sec_data.key?("rotation")
          
          seat_section.save!
          section_ids_in_use << seat_section.id
          
          # Store mapping from original ID to database ID
          orig_id_to_db_id_map[original_id.to_s] = seat_section.id
          
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
        
        # Now add _original_id to each section in sections_data to help with shape matching
        if layout.sections_data && layout.sections_data["sections"].is_a?(Array)
          # Update sections in sections_data to store both original and database IDs
          layout.sections_data["sections"].each do |json_section|
            original_id = json_section["id"].to_s
            if orig_id_to_db_id_map[original_id]
              # Add database ID and original ID as metadata
              json_section["database_id"] = orig_id_to_db_id_map[original_id]
              json_section["original_id"] = original_id
            end
          end
        end
        
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

  # Activate a layout for a specific location or restaurant
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
      
      # If layout is associated with a location, set it as active for that location
      if layout.location_id.present?
        location = Location.find_by(id: layout.location_id)
        
        if location.nil?
          return { success: false, errors: ["Associated location not found"], status: :not_found }
        end
        
        # Update the location's current layout
        location.update!(current_layout_id: layout.id)
        
        { 
          success: true, 
          message: "Layout #{layout.name} (ID #{layout.id}) is now active for Location #{location.name} (ID #{location.id})" 
        }
      else
        # For backwards compatibility, if no location_id is specified, update at restaurant level
        layout.restaurant.update!(current_layout_id: layout.id)
        
        { 
          success: true, 
          message: "Layout #{layout.name} (ID #{layout.id}) is now active for Restaurant #{layout.restaurant_id}" 
        }
      end
    rescue => e
      { success: false, errors: ["Failed to activate layout: #{e.message}"], status: :internal_server_error }
    end
  end
end
