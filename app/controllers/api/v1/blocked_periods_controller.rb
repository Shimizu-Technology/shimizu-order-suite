# app/controllers/api/v1/blocked_periods_controller.rb
module Api
  module V1
    class BlockedPeriodsController < ApiController
      include TenantIsolation
      before_action :set_blocked_period, only: [:show, :update, :destroy]
      before_action :ensure_tenant_context
      
      # GET /api/v1/blocked_periods
      def index
        # Scope to current restaurant for tenant isolation
        @blocked_periods = BlockedPeriod.where(restaurant: current_restaurant)
        
        # Filter by location if provided
        if params[:location_id].present?
          @blocked_periods = @blocked_periods.where(location_id: params[:location_id])
        end
        
        # Filter by active status
        if params[:active].present? && params[:active] == 'true'
          @blocked_periods = @blocked_periods.active
        end
        
        # Filter by date range if provided
        if params[:start_date].present? && params[:end_date].present?
          start_date = Date.parse(params[:start_date])
          end_date = Date.parse(params[:end_date])
          @blocked_periods = @blocked_periods.where('DATE(start_time) <= ? AND DATE(end_time) >= ?', end_date, start_date)
        end
        
        render json: @blocked_periods
      end
      
      # GET /api/v1/blocked_periods/:id
      def show
        render json: @blocked_period
      end
      
      # POST /api/v1/blocked_periods
      def create
        # Ensure restaurant_id is set
        blocked_period_params_with_tenant = blocked_period_params.merge(restaurant_id: current_restaurant.id)
        
        @blocked_period = BlockedPeriod.new(blocked_period_params_with_tenant)
        
        if @blocked_period.save
          render json: @blocked_period, status: :created
        else
          render json: { errors: @blocked_period.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # PATCH/PUT /api/v1/blocked_periods/:id
      def update
        if @blocked_period.update(blocked_period_params)
          render json: @blocked_period
        else
          render json: { errors: @blocked_period.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      # DELETE /api/v1/blocked_periods/:id
      def destroy
        if @blocked_period.destroy
          render json: { message: "Blocked period successfully deleted" }
        else
          render json: { errors: @blocked_period.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      private
      
      def set_blocked_period
        # Scope to current restaurant for tenant isolation
        @blocked_period = BlockedPeriod.where(restaurant: current_restaurant).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Blocked period not found" }, status: :not_found
      end
      
      def blocked_period_params
        params.require(:blocked_period).permit(
          :location_id, 
          :seat_section_id, 
          :start_time, 
          :end_time, 
          :reason, 
          :status, 
          :restaurant_id,
          metadata: {}
        )
      end
    end
  end
end
