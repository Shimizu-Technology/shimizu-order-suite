# app/controllers/availability_controller.rb

class AvailabilityController < ApplicationController
  include TenantIsolation
  
  before_action :optional_authorize
  before_action :ensure_tenant_context, except: [:index]
  # GET /availability?date=YYYY-MM-DD&party_size=4&restaurant_id=1
  def index
    date_str = params[:date]
    party_size = params[:party_size].to_i
    
    # Get restaurant from current context or from params
    if current_restaurant.present?
      # Use the current restaurant context
      result = availability_service.available_time_slots(date_str, party_size)
    elsif params[:restaurant_id].present?
      # Find the restaurant by ID and create a temporary service
      restaurant = Restaurant.find_by(id: params[:restaurant_id])
      if restaurant.nil?
        render json: { error: "Restaurant not found" }, status: :not_found
        return
      end
      
      temp_service = AvailabilityService.new(restaurant)
      temp_service.current_user = current_user if current_user.present?
      result = temp_service.available_time_slots(date_str, party_size)
    else
      render json: { error: "Restaurant ID is required" }, status: :unprocessable_entity
      return
    end
    
    if result[:success]
      render json: {
        slots: result[:available_slots].map { |slot| slot[:time] }
      }
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  # GET /availability/operating_hours
  def operating_hours
    result = availability_service.get_operating_hours
    
    if result[:success]
      render json: { operating_hours: result[:operating_hours] }
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end
  
  # PUT /availability/operating_hours
  def update_operating_hours
    unless current_user && %w[admin super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: admin only" }, status: :forbidden
    end
    
    result = availability_service.update_operating_hours(params[:operating_hours])
    
    if result[:success]
      render json: { operating_hours: result[:operating_hours] }
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # GET /availability/check?date=YYYY-MM-DD&time=HH:MM&party_size=4
  def check
    date = params[:date]
    time = params[:time]
    party_size = params[:party_size].to_i
    
    result = availability_service.check_availability(date, time, party_size)
    
    if result[:success]
      render json: { 
        available: result[:available],
        reason: result[:reason],
        available_seats: result[:available_seats],
        total_seats: result[:total_seats]
      }
    else
      render json: { error: result[:errors].join(", ") }, status: result[:status] || :internal_server_error
    end
  end

  private
  
  def availability_service
    @availability_service ||= begin
      service = AvailabilityService.new(current_restaurant)
      service.current_user = current_user if current_user.present?
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
