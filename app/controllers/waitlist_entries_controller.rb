# app/controllers/waitlist_entries_controller.rb

class WaitlistEntriesController < ApplicationController
  before_action :authorize_request

  def index
    # Only staff/admin/super_admin can list the entire waitlist
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    scope = WaitlistEntry.where(restaurant_id: current_user.restaurant_id)

    # If ?date=YYYY-MM-DD is given, filter by local date for check_in_time
    if params[:date].present?
      begin
        date_filter = Date.parse(params[:date])

        restaurant = Restaurant.find(current_user.restaurant_id)
        tz = restaurant.time_zone.presence || "Pacific/Guam"

        start_local = Time.use_zone(tz) do
          Time.zone.local(date_filter.year, date_filter.month, date_filter.day, 0, 0, 0)
        end
        end_local = start_local.end_of_day

        start_utc = start_local.utc
        end_utc   = end_local.utc

        # Show waitlist entries whose check_in_time is in [start_utc..end_utc)
        scope = scope.where("check_in_time >= ? AND check_in_time < ?", start_utc, end_utc)
      rescue ArgumentError
        Rails.logger.warn "[WaitlistEntriesController#index] invalid date param=#{params[:date]}"
        # optionally: scope = scope.none
      end
    end

    waitlist = scope.all
    render json: waitlist
  end

  def show
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    entry = WaitlistEntry.find(params[:id])
    render json: entry
  end

  def create
    # If guests can create waitlist entries, skip :authorize_request or handle differently
    entry = WaitlistEntry.new(waitlist_entry_params)
    # Force restaurant if desired:
    entry.restaurant_id = current_user.restaurant_id

    if entry.save
      render json: entry, status: :created
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    entry = WaitlistEntry.find(params[:id])
    if entry.update(waitlist_entry_params)
      render json: entry
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    entry = WaitlistEntry.find(params[:id])
    entry.destroy
    head :no_content
  end

  private

  def waitlist_entry_params
    params.require(:waitlist_entry).permit(
      :restaurant_id,
      :contact_name,
      :party_size,
      :check_in_time,
      :status,
      :contact_phone
    )
  end
end
