# app/controllers/availability_controller.rb

class AvailabilityController < ApplicationController
  include TenantIsolation
  
  before_action :optional_authorize
  before_action :ensure_tenant_context, except: [:index]
  # GET /availability?date=YYYY-MM-DD&party_size=4&restaurant_id=1
  def index
    date_str = params[:date]
    party_size = params[:party_size].to_i
    location_id = params[:location_id]
    
    # Get restaurant from current context or from params
    if current_restaurant.present?
      # Use the current restaurant context
      result = availability_service.available_time_slots(date_str, party_size, location_id)
    elsif params[:restaurant_id].present?
      # Find the restaurant by ID and create a temporary service
      restaurant = Restaurant.find_by(id: params[:restaurant_id])
      if restaurant.nil?
        render json: { error: "Restaurant not found" }, status: :not_found
        return
      end
      
      temp_service = AvailabilityService.new(restaurant)
      temp_service.current_user = current_user if current_user.present?
      result = temp_service.available_time_slots(date_str, party_size, location_id)
    else
      render json: { error: "Restaurant ID is required" }, status: :unprocessable_entity
      return
    end
    
    if result[:success]
      # Get the maximum available seats across all time slots
      max_available_seats = 0
      
      if result[:available_slots].any?
        # Find the time slot with the most available seats
        max_available_seats = result[:available_slots].map { |slot| slot[:available_seats] || 0 }.max
      end
      
      response_data = {
        slots: result[:available_slots].map { |slot| slot[:time] },
        max_available_seats: max_available_seats
      }
      
      # Include capacity information if requested
      if params[:get_capacity].present? && params[:get_capacity].to_s.downcase == 'true'
        restaurant_obj = current_restaurant.present? ? current_restaurant : Restaurant.find_by(id: params[:restaurant_id])
        if restaurant_obj
          physical_capacity = restaurant_obj.current_seats.count
          admin_max_party_size = restaurant_obj.admin_settings&.dig("reservations", "max_party_size") || restaurant_obj.max_party_size || 20
          
          # Use the lower of physical capacity and admin-configured max party size
          effective_max_party_size = [physical_capacity, admin_max_party_size].min
          
          # Limit max_available_seats to the admin-configured max party size
          max_available_seats = [max_available_seats, admin_max_party_size].min
          
          # Add all capacity-related information to the response
          response_data[:actual_capacity] = physical_capacity
          response_data[:admin_max_party_size] = admin_max_party_size
          response_data[:effective_max_party_size] = effective_max_party_size
          response_data[:max_available_seats] = max_available_seats
          
          Rails.logger.info "AVAILABILITY: Including actual capacity of #{physical_capacity} seats in response"
          Rails.logger.info "AVAILABILITY: Admin configured max party size: #{admin_max_party_size}"
          Rails.logger.info "AVAILABILITY: Effective max party size: #{effective_max_party_size}"
          Rails.logger.info "AVAILABILITY: Maximum available seats for any time slot: #{max_available_seats}"
        end
      end
      
      render json: response_data
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
  
  # GET /availability/simple_capacity?restaurant_id=1
  # Returns the actual physical seating capacity of the restaurant
  def simple_capacity
    restaurant_obj = current_restaurant.present? ? current_restaurant : Restaurant.find_by(id: params[:restaurant_id])
    
    if restaurant_obj.nil?
      render json: { error: "Restaurant not found" }, status: :not_found
      return
    end
    
    # Get the actual number of seats from the restaurant's layout
    physical_capacity = restaurant_obj.current_seats.count
    admin_max_party_size = restaurant_obj.admin_settings&.dig("reservations", "max_party_size") || restaurant_obj.max_party_size || 20
    
    # The effective max party size is the lower of physical capacity and admin setting
    effective_max_party_size = [physical_capacity, admin_max_party_size].min
    
    render json: {
      actual_capacity: physical_capacity,
      admin_max_party_size: admin_max_party_size,
      effective_max_party_size: effective_max_party_size
    }
  end

  # GET /availability/capacity?date=YYYY-MM-DD&time=HH:MM&restaurant_id=1&party_size=2
  # Returns the maximum party size that can be accommodated for a given date and time
  def capacity
    date_str = params[:date]
    time_str = params[:time]
    location_id = params[:location_id]
    party_size = params[:party_size].present? ? params[:party_size].to_i : 2 # Default to 2 if not provided
    
    Rails.logger.info "CAPACITY CHECK: Checking capacity for date=#{date_str}, time=#{time_str}, party_size=#{party_size}"
    
    # Get restaurant from current context or from params
    if current_restaurant.present?
      # Use the current restaurant context
      result = availability_service.max_party_size(date_str, time_str, location_id, party_size)
    elsif params[:restaurant_id].present?
      # Find the restaurant by ID and create a temporary service
      restaurant = Restaurant.find_by(id: params[:restaurant_id])
      if restaurant.nil?
        render json: { error: "Restaurant not found" }, status: :not_found
        return
      end
      
      temp_service = AvailabilityService.new(restaurant)
      temp_service.current_user = current_user if current_user.present?
      result = temp_service.max_party_size(date_str, time_str, location_id, party_size)
    else
      render json: { error: "Restaurant ID is required" }, status: :unprocessable_entity
      return
    end
    
    if result[:success]
      # Create response payload
      response_data = {
        max_party_size: result[:max_party_size],
        available: result[:available], 
        total_capacity: result[:total_capacity],
        booked_seats: result[:booked_seats]
      }
      
      # Enhanced debug logging
      Rails.logger.info "CAPACITY RESPONSE WITH CONTEXT: #{response_data.inspect}"
      Rails.logger.info "CAPACITY CALCULATION DETAILS: For #{date_str} at #{time_str}, party_size=#{party_size}, location_id=#{location_id || 'not specified'}"
      if !result[:available] && result[:reason].present?
        Rails.logger.info "CAPACITY REASON: #{result[:reason]}"
      end
      
      # Debug log the response data
      Rails.logger.info "CAPACITY RESPONSE: #{response_data.inspect}"
      
      render json: response_data
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
