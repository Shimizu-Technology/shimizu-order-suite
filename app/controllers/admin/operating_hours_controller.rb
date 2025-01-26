# app/controllers/admin/operating_hours_controller.rb

module Admin
  class OperatingHoursController < ApplicationController
    before_action :authorize_request
    before_action :require_admin

    # GET /admin/operating_hours
    # => lists all OperatingHour records for the current_user’s restaurant
    def index
      restaurant = current_user.restaurant
      oh = restaurant.operating_hours.order(:day_of_week)
      render json: oh
    end

    # PATCH/PUT /admin/operating_hours/:id => update a single day-of-week row
    def update
      oh = OperatingHour.find(params[:id])
      unless oh.restaurant_id == current_user.restaurant_id
        return render json: { error: "Forbidden" }, status: :forbidden
      end

      if oh.update(oh_params)
        render json: oh
      else
        render json: { errors: oh.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def require_admin
      unless current_user.role.in?(%w[admin super_admin])
        render json: { error: "Forbidden: admin only" }, status: :forbidden
      end
    end

    def oh_params
      # Permit the fields we allow staff to change
      params.require(:operating_hour).permit(:day_of_week, :open_time, :close_time, :closed)
    end
  end
end
