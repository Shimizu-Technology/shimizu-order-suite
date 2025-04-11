# app/controllers/seats_controller.rb
class SeatsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  def index
    result = seat_service.list_seats(params[:seat_section_id])
    
    if result[:success]
      render json: result[:seats]
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  def show
    result = seat_service.find_seat(params[:id])
    
    if result[:success]
      render json: result[:seat]
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :not_found
    end
  end

  def create
    seat_params = params.require(:seat).permit(
      :seat_section_id, :label, :position_x, :position_y, :capacity
    ).to_h
    
    result = seat_service.create_seat(seat_params)
    
    if result[:success]
      render json: result[:seat], status: :created
    else
      Rails.logger.error("Failed to create seat: #{result[:errors].join(", ")}")
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def update
    update_params = params.require(:seat).permit(
      :label, :position_x, :position_y, :capacity, :seat_section_id
    ).to_h
    
    result = seat_service.update_seat(params[:id], update_params)
    
    if result[:success]
      render json: result[:seat]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def destroy
    result = seat_service.delete_seat(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end

  def bulk_update
    # Expect an array of seat objects: [ { id: 1, label: "A1" }, { id: 2, label: "B1" }, ... ]
    seat_params_array = params.require(:seats)
    updated_records = []
    errors = []
    
    ActiveRecord::Base.transaction do
      seat_params_array.each do |seat_data|
        safe_data = seat_data.permit(:id, :label, :position_x, :position_y, :capacity).to_h
        seat_id = safe_data.delete(:id)
        
        if seat_id.blank?
          errors << "Seat ID is required"
          next
        end
        
        # Update the seat using the service
        result = seat_service.update_seat(seat_id, safe_data)
        
        unless result[:success]
          errors << "Seat ID=#{seat_id} => #{result[:errors].join(", ")}"
        else
          updated_records << result[:seat]
        end
      end
      
      raise ActiveRecord::Rollback if errors.any?
    end
    
    if errors.any?
      render json: { errors: errors }, status: :unprocessable_entity
    else
      render json: updated_records, status: :ok
    end
  end
  
  # POST /seats/:id/allocate
  def allocate
    allocation_params = params.require(:allocation).permit(
      :reservation_id, :waitlist_entry_id
    ).to_h
    
    result = seat_service.allocate_seat(params[:id], allocation_params)
    
    if result[:success]
      render json: result[:allocation], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /seats/:id/release
  def release
    result = seat_service.release_seat(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
  def seat_service
    @seat_service ||= begin
      service = SeatService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
