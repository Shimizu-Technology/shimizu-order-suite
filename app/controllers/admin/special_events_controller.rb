# app/controllers/admin/special_events_controller.rb

module Admin
  class SpecialEventsController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request
    before_action :require_admin!
    before_action :ensure_tenant_context

    def index
      # Use the SpecialEventsService to get events with tenant isolation
      events = special_events_service.list_events
      render json: events
    end

    def show
      # Use the SpecialEventsService to get a specific event with tenant isolation
      event = special_events_service.get_event(params[:id])
      render json: event
    end

    def create
      # Use the SpecialEventsService to create an event with tenant isolation
      result = special_events_service.create_event(event_params)
      
      if result[:success]
        render json: result[:event], status: result[:status] || :created
      else
        render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
      end
    end

    def update
      # Use the SpecialEventsService to update an event with tenant isolation
      result = special_events_service.update_event(params[:id], event_params)
      
      if result[:success]
        render json: result[:event]
      else
        render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
      end
    end

    def destroy
      # Use the SpecialEventsService to delete an event with tenant isolation
      result = special_events_service.delete_event(params[:id])
      head :no_content
    end

    private

    def require_admin!
      unless current_user && %w[admin super_admin].include?(current_user.role)
        render json: { error: "Forbidden: admin only" }, status: :forbidden
      end
    end
    
    def special_events_service
      @special_events_service ||= SpecialEventsService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end

    def event_params
      params.require(:special_event).permit(
        :event_date,
        :exclusive_booking,
        :max_capacity,
        :description,
        :closed,
        :start_time,
        :end_time
      )
    end
  end
end
