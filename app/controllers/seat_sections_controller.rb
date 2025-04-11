# app/controllers/seat_sections_controller.rb

class SeatSectionsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  def index
    result = seat_section_service.list_seat_sections(params[:layout_id])
    
    if result[:success]
      render json: result[:seat_sections]
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  def show
    result = seat_section_service.find_seat_section(params[:id])
    
    if result[:success]
      render json: result[:seat_section]
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :not_found
    end
  end

  def create
    # Process the section parameters
    section_params = prepare_section_params
    
    # Add auto-generated seats if it's a table with capacity > 1
    if section_params[:section_type] == "table" && 
       section_params[:capacity].present? && 
       section_params[:capacity] > 1
      
      section_params[:seats] = generate_table_seats_params(section_params)
    end
    
    # Create the seat section using the service
    result = seat_section_service.create_seat_section(section_params)
    
    if result[:success]
      render json: result[:seat_section], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def update
    # Process the section parameters
    update_params = prepare_update_params
    
    # Update the seat section using the service
    result = seat_section_service.update_seat_section(params[:id], update_params)
    
    if result[:success]
      render json: result[:seat_section]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def destroy
    result = seat_section_service.delete_seat_section(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end

  private
  
  def seat_section_service
    @seat_section_service ||= begin
      service = SeatSectionService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
  
  def prepare_section_params
    params.require(:seat_section).permit(
      :layout_id,
      :name,
      :section_type,
      :orientation,
      :offset_x,
      :offset_y,
      :capacity,
      :floor_number
    ).to_h
  end
  
  def prepare_update_params
    params.require(:seat_section).permit(
      :name,
      :section_type,
      :orientation,
      :offset_x,
      :offset_y,
      :capacity,
      :floor_number
    ).to_h
  end
  
  # Generate seat parameters for a table
  def generate_table_seats_params(section_params)
    # e.g. place them in a line, or a small circle around offset_x, offset_y
    # We'll do a trivial line, each seat 40px right from the last:
    base_x = 0
    base_y = 0
    seats = []
    
    (1..section_params[:capacity]).each do |i|
      seats << {
        label: "#{section_params[:name]}#{i}",
        position_x: base_x + 40 * (i - 1),  # e.g. horizontally spaced
        position_y: base_y,
        capacity: 1
      }
    end
    
    seats
  end
end
