# app/controllers/admin/special_events_controller.rb

module Admin
  class SpecialEventsController < ApplicationController
    before_action :authorize_request
    before_action :require_admin!

    def index
      events = current_user.restaurant.special_events.order(:event_date)
      render json: events
    end

    def show
      event = current_user.restaurant.special_events.find(params[:id])
      render json: event
    end

    def create
      event = current_user.restaurant.special_events.new(event_params)
      if event.save
        render json: event, status: :created
      else
        render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      event = current_user.restaurant.special_events.find(params[:id])
      if event.update(event_params)
        render json: event
      else
        render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      event = current_user.restaurant.special_events.find(params[:id])
      event.destroy
      head :no_content
    end

    private

    def require_admin!
      unless current_user && %w[admin super_admin].include?(current_user.role)
        render json: { error: "Forbidden: admin only" }, status: :forbidden
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
