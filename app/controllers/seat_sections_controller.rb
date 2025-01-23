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

  def create
    section_params = params.require(:seat_section).permit(
      :layout_id, :name, :section_type, :orientation, :offset_x, :offset_y, :capacity
    )
    seat_section = SeatSection.new(section_params)

    if seat_section.save
      render json: seat_section, status: :created
    else
      render json: { errors: seat_section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    seat_section = SeatSection.find_by(id: params[:id])
    return render json: { error: "Seat section not found" }, status: :not_found unless seat_section

    update_params = params.require(:seat_section).permit(
      :name, :section_type, :orientation, :offset_x, :offset_y, :capacity
    )
    if seat_section.update(update_params)
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
end
