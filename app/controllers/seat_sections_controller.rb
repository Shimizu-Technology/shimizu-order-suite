# app/controllers/seat_sections_controller.rb

class SeatSectionsController < ApplicationController
  before_action :authorize_request

  def index
    if params[:layout_id]
      seat_sections = SeatSection.where(layout_id: params[:layout_id])
      render json: seat_sections
    else
      render json: SeatSection.all
    end
  end

  def show
    seat_section = SeatSection.find_by(id: params[:id])
    return render json: { error: "Seat section not found" }, status: :not_found unless seat_section

    render json: seat_section
  end

  #-------------------------------------------------------------------
  # CREATE
  # Optional snippet: if section_type == 'table' and capacity > 0,
  # auto-generate N seats in a small row (or circle) as a convenience.
  #-------------------------------------------------------------------
  def create
    section_params = params.require(:seat_section).permit(
      :layout_id,
      :name,
      :section_type,
      :orientation,
      :offset_x,
      :offset_y,
      :capacity,
      :floor_number      # <-- Added here
    )

    seat_section = SeatSection.new(section_params)

    if seat_section.save
      # --------------------------------------------------------------
      # [OPTIONAL] Auto-create seats if it's a table with capacity>1
      # --------------------------------------------------------------
      if seat_section.section_type == "table" &&
         seat_section.capacity.present? &&
         seat_section.capacity > 1

        auto_generate_table_seats(seat_section)
      end

      render json: seat_section, status: :created
    else
      render json: { errors: seat_section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    seat_section = SeatSection.find_by(id: params[:id])
    return render json: { error: "Seat section not found" }, status: :not_found unless seat_section

    update_params = params.require(:seat_section).permit(
      :name,
      :section_type,
      :orientation,
      :offset_x,
      :offset_y,
      :capacity,
      :floor_number      # <-- Added here as well
    )

    if seat_section.update(update_params)
      # If you want to re-generate seats every time user changes capacity,
      # do something like:
      # seat_section.seats.destroy_all
      # auto_generate_table_seats(seat_section)
      # (But that might nuke user-labeled seats, so be cautious.)

      render json: seat_section
    else
      render json: { errors: seat_section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    seat_section = SeatSection.find_by(id: params[:id])
    return head :no_content unless seat_section

    seat_section.destroy
    head :no_content
  end

  private

  #-----------------------------------------------------------
  # Example method to auto-generate seat records for a "table."
  # You can adapt the geometry or labeling as you wish.
  #-----------------------------------------------------------
  def auto_generate_table_seats(seat_section)
    # e.g. place them in a line, or a small circle around offset_x, offset_y
    # We'll do a trivial line, each seat 40px right from the last:
    base_x = 0
    base_y = 0

    (1..seat_section.capacity).each do |i|
      seat_section.seats.create!(
        label: "#{seat_section.name}#{i}",
        position_x: base_x + 40 * (i - 1),  # e.g. horizontally spaced
        position_y: base_y,
        capacity: 1
      )
    end
  end
end
