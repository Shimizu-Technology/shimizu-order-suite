# app/controllers/layouts_controller.rb
class LayoutsController < ApplicationController
  before_action :authorize_request
  before_action :set_layout, only: [ :show, :update, :destroy, :activate ]

  # GET /layouts
  def index
    if current_user.role == "super_admin"
      layouts = Layout.all
    else
      layouts = Layout.where(restaurant_id: current_user.restaurant_id)
    end
    render json: layouts
  end

  # GET /layouts/:id
  def show
    seat_sections = @layout.seat_sections.includes(:seats)

    # Grab seat allocations still active.
    seat_allocations = SeatAllocation
      .includes(:reservation, :waitlist_entry)
      .where(seat_id: seat_sections.flat_map(&:seats).pluck(:id), released_at: nil)

    occupant_map = {}
    seat_allocations.each do |alloc|
      occupant = alloc.reservation || alloc.waitlist_entry
      occupant_map[alloc.seat_id] = {
        occupant_type:       alloc.reservation_id ? "reservation" : "waitlist",
        occupant_name:       occupant.contact_name,
        occupant_party_size: occupant.try(:party_size),
        occupant_status:     occupant.status
      }
    end

    # Re-build a consistent 'sections_data' that includes floor_number
    # so the front-end sees it in the "sections_data" JSON.
    rebuilt_sections_data = {
      sections: seat_sections.map do |sec|
        {
          id:          sec.id.to_s, # or just sec.id if you prefer
          name:        sec.name,
          type:        sec.section_type,  # "table" or "counter"
          orientation: sec.orientation,
          offsetX:     sec.offset_x,
          offsetY:     sec.offset_y,
          floorNumber: sec.floor_number,
          seats: sec.seats.map do |seat|
            {
              id:         seat.id,
              label:      seat.label,
              position_x: seat.position_x,
              position_y: seat.position_y,
              capacity:   seat.capacity
            }
          end
        }
      end
    }

    data = {
      id:            @layout.id,
      name:          @layout.name,
      sections_data: rebuilt_sections_data,  # replace raw @layout.sections_data
      seat_sections: seat_sections.map do |sec|
        {
          id:           sec.id,
          name:         sec.name,
          section_type: sec.section_type,
          offset_x:     sec.offset_x,
          offset_y:     sec.offset_y,
          orientation:  sec.orientation,
          floor_number: sec.floor_number,

          seats: sec.seats.map do |seat|
            occ = occupant_map[seat.id]
            {
              id:         seat.id,
              label:      seat.label,
              position_x: seat.position_x,
              position_y: seat.position_y,
              capacity:   seat.capacity,
              status:     occ ? "occupied" : "free",
              occupant_info: occ
            }
          end
        }
      end
    }

    render json: data
  end

  # POST /layouts
  def create
    assigned_restaurant_id =
      if current_user.role == "super_admin"
        layout_params[:restaurant_id]
      else
        current_user.restaurant_id
      end

    @layout = Layout.new(
      name:           layout_params[:name],
      restaurant_id:  assigned_restaurant_id,
      sections_data:  layout_params[:sections_data] || {}
    )

    ActiveRecord::Base.transaction do
      if @layout.save!
        sections_array = layout_params.dig(:sections_data, :sections) || []
        section_ids_in_use = []

        sections_array.each do |sec_data|
          existing_section_id = sec_data["id"].to_i if sec_data["id"].to_s.match?(/^\d+$/)
          seat_section = existing_section_id && existing_section_id > 0 ?
                           @layout.seat_sections.find_by(id: existing_section_id) : nil
          seat_section ||= @layout.seat_sections.build

          seat_section.name         = sec_data["name"]
          seat_section.section_type = sec_data["type"]       # "table" or "counter"
          seat_section.orientation  = sec_data["orientation"]
          seat_section.offset_x     = sec_data["offsetX"]
          seat_section.offset_y     = sec_data["offsetY"]

          # Always set floor_number if the client sends it:
          seat_section.floor_number = sec_data["floorNumber"] if sec_data.key?("floorNumber")

          seat_section.save!
          section_ids_in_use << seat_section.id

          seats_array    = sec_data["seats"] || []
          seat_ids_in_use = []
          seats_array.each do |seat_data|
            existing_seat_id = seat_data["id"].to_i if seat_data["id"].to_s.match?(/^\d+$/)
            seat = existing_seat_id && existing_seat_id > 0 ?
                     seat_section.seats.find_by(id: existing_seat_id) : nil
            seat ||= seat_section.seats.build

            seat.label       = seat_data["label"]
            seat.position_x  = seat_data["position_x"]
            seat.position_y  = seat_data["position_y"]
            seat.capacity    = seat_data["capacity"] || 1
            seat.save!

            seat_ids_in_use << seat.id
          end

          # remove any seats that are no longer in the incoming array
          seat_section.seats.where.not(id: seat_ids_in_use).destroy_all
        end

        # Clean up old sections not in use
        @layout.seat_sections.where.not(id: section_ids_in_use).destroy_all
        @layout.save!

        render json: @layout, status: :created
      else
        render json: { errors: @layout.errors.full_messages }, status: :unprocessable_entity
      end
    end
  rescue => e
    Rails.logger.error("Layout creation failed => #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH/PUT /layouts/:id
  def update
    if current_user.role != "super_admin"
      @layout.restaurant_id = current_user.restaurant_id
    elsif layout_params[:restaurant_id].present?
      @layout.restaurant_id = layout_params[:restaurant_id]
    end

    @layout.name = layout_params[:name] if layout_params[:name]
    @layout.sections_data = layout_params[:sections_data] if layout_params.key?(:sections_data)

    sections_array = layout_params.dig(:sections_data, :sections) || []

    ActiveRecord::Base.transaction do
      section_ids_in_use = []

      sections_array.each do |sec_data|
        existing_section_id = sec_data["id"].to_i if sec_data["id"].to_s.match?(/^\d+$/)
        seat_section = existing_section_id && existing_section_id > 0 ?
                         @layout.seat_sections.find_by(id: existing_section_id) : nil
        seat_section ||= @layout.seat_sections.build

        seat_section.name         = sec_data["name"]
        seat_section.section_type = sec_data["type"]
        seat_section.orientation  = sec_data["orientation"]
        seat_section.offset_x     = sec_data["offsetX"]
        seat_section.offset_y     = sec_data["offsetY"]
        # Always set floor_number if the client sends it
        seat_section.floor_number = sec_data["floorNumber"] if sec_data.key?("floorNumber")

        seat_section.save!
        section_ids_in_use << seat_section.id

        seats_array   = sec_data["seats"] || []
        seat_ids_in_use = []
        seats_array.each do |seat_data|
          existing_seat_id = seat_data["id"].to_i if seat_data["id"].to_s.match?(/^\d+$/)
          seat = existing_seat_id && existing_seat_id > 0 ?
                   seat_section.seats.find_by(id: existing_seat_id) : nil
          seat ||= seat_section.seats.build

          seat.label       = seat_data["label"]
          seat.position_x  = seat_data["position_x"]
          seat.position_y  = seat_data["position_y"]
          seat.capacity    = seat_data["capacity"] || 1
          seat.save!

          seat_ids_in_use << seat.id
        end

        seat_section.seats.where.not(id: seat_ids_in_use).destroy_all
      end

      # remove old seat_sections not in use
      @layout.seat_sections.where.not(id: section_ids_in_use).destroy_all
      @layout.save!
    end

    render json: @layout
  rescue => e
    Rails.logger.error("Error updating layout with seat sections: #{e.message}")
    render json: { errors: [ e.message ] }, status: :unprocessable_entity
  end

  # DELETE /layouts/:id
  def destroy
    @layout.destroy
    head :no_content
  end

  # POST /layouts/:id/activate
  def activate
    unless current_user.role.in?(%w[admin staff super_admin])
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    if @layout.restaurant_id != current_user.restaurant_id && current_user.role != "super_admin"
      return render json: { error: "Layout does not belong to your restaurant" }, status: :forbidden
    end

    @layout.restaurant.update!(current_layout_id: @layout.id)

    render json: {
      message: "Layout #{@layout.name} (ID #{@layout.id}) is now active for Restaurant #{@layout.restaurant_id}"
    }, status: :ok
  end

  private

  def public_endpoint?
    # Allow access to layouts for authenticated users
    # For index and other actions, we need to ensure the user has a valid restaurant context
    # or is a super_admin with a restaurant_id parameter
    if current_user
      if current_user.role == 'super_admin'
        return params[:restaurant_id].present? || params[:id].present?
      else
        return %w[admin staff].include?(current_user.role) && current_user.restaurant_id.present?
      end
    end
    false
  end

  def set_layout
    @layout = Layout.find(params[:id])
  end

  def layout_params
    params.require(:layout).permit(:name, :restaurant_id, sections_data: {})
  end
end
