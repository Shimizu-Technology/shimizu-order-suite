# app/controllers/api/v1/location_capacities_controller.rb
module Api
  module V1
    class LocationCapacitiesController < ApiController
      include TenantIsolation
      before_action :set_location_capacity, only: [:show, :update]
      before_action :ensure_tenant_context
      
      # GET /api/v1/location_capacities
      def index
        # Scope to current restaurant for tenant isolation
        @location_capacities = LocationCapacity.where(restaurant: current_restaurant).includes(:location)
        
        # Filter by location if provided
        if params[:location_id].present?
          @location_capacities = @location_capacities.where(location_id: params[:location_id])
        end
        
        render json: @location_capacities
      end
      
      # GET /api/v1/location_capacities/:id
      def show
        render json: @location_capacity
      end
      
      # POST /api/v1/location_capacities
      def create
        # Ensure restaurant_id is set
        capacity_params_with_tenant = location_capacity_params.merge(restaurant_id: current_restaurant.id)
        
        @location_capacity = LocationCapacity.new(capacity_params_with_tenant)
        
        if @location_capacity.save
          render json: @location_capacity, status: :created
        else
          render json: { errors: @location_capacity.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # PATCH/PUT /api/v1/location_capacities/:id
      def update
        if @location_capacity.update(location_capacity_params)
          render json: @location_capacity
        else
          render json: { errors: @location_capacity.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # GET /api/v1/locations/:location_id/available_capacity
      def available_capacity
        location_id = params[:location_id]
        date = params[:date]
        time = params[:time]
        
        # Validate parameters
        unless location_id.present? && date.present? && time.present?
          return render json: { error: "Location ID, date, and time are required" }, status: :bad_request
        end
        
        # Check if location is valid and belongs to current restaurant
        location = Location.where(restaurant: current_restaurant).find_by(id: location_id)
        unless location
          return render json: { error: "Location not found or not associated with this restaurant" }, status: :not_found
        end
        
        # Find or initialize capacity
        location_capacity = LocationCapacity.find_or_initialize_by(
          restaurant_id: current_restaurant.id,
          location_id: location_id
        )
        
        # If it's a new record, set default values but don't save yet
        if location_capacity.new_record?
          location_capacity.total_capacity = 26
          location_capacity.default_table_capacity = 4
        end
        
        # Create a datetime object from date and time
        begin
          date_obj = Date.parse(date)
          time_obj = Time.parse(time)
          
          datetime = Time.new(
            date_obj.year, 
            date_obj.month, 
            date_obj.day, 
            time_obj.hour, 
            time_obj.min, 
            time_obj.sec
          )
          
          # Get available capacity at this time
          available = location_capacity.available_capacity_at(datetime)
          
          render json: { 
            total_capacity: location_capacity.total_capacity,
            available_capacity: available,
            datetime: datetime
          }
        rescue => e
          render json: { error: "Invalid date or time format: #{e.message}" }, status: :bad_request
        end
      end
      
      private
      
      def set_location_capacity
        # Scope to current restaurant for tenant isolation
        @location_capacity = LocationCapacity.where(restaurant: current_restaurant).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Location capacity not found" }, status: :not_found
      end
      
      def location_capacity_params
        params.require(:location_capacity).permit(
          :location_id, 
          :total_capacity, 
          :default_table_capacity, 
          capacity_metadata: {}
        )
      end
    end
  end
end
