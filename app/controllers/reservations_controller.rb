# app/controllers/reservations_controller.rb

class ReservationsController < ApplicationController
  before_action :authorize_request, except: [:create]

  def index
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    scope = Reservation.where(restaurant_id: current_user.restaurant_id)

    # If ?date=YYYY-MM-DD was provided, filter by local day in "Pacific/Guam" (or the restaurant's tz)
    if params[:date].present?
      begin
        date_filter = Date.parse(params[:date])

        # If you want to load the actual restaurant and use its time_zone:
        restaurant = Restaurant.find(current_user.restaurant_id)
        tz = restaurant.time_zone.presence || "Pacific/Guam"

        # Build local start_of_day..end_of_day, then convert to UTC
        start_local = Time.use_zone(tz) do
          Time.zone.local(date_filter.year, date_filter.month, date_filter.day, 0, 0, 0)
        end
        end_local = start_local.end_of_day

        start_utc = start_local.utc
        end_utc   = end_local.utc

        # Return only reservations whose start_time is within [start_utc..end_utc)
        scope = scope.where("start_time >= ? AND start_time < ?", start_utc, end_utc)
      rescue ArgumentError
        Rails.logger.warn "[ReservationsController#index] invalid date param=#{params[:date]}"
        # optionally: scope = scope.none
      end
    end

    reservations = scope.all
    render json: reservations
  end

  def show
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])
    render json: reservation
  end

  # CREATE = public
  def create
    # Build from strong params
    @reservation = Reservation.new

    # Parse incoming start_time/end_time as local times (Guam)
    if reservation_params[:start_time].present?
      parsed_start = Time.zone.parse(reservation_params[:start_time])
      if parsed_start.nil?
        return render json: { error: "Invalid start_time format" }, status: :unprocessable_entity
      end
      @reservation.start_time = parsed_start
    end

    if reservation_params[:end_time].present?
      parsed_end = Time.zone.parse(reservation_params[:end_time])
      if parsed_end.nil?
        return render json: { error: "Invalid end_time format" }, status: :unprocessable_entity
      end
      @reservation.end_time = parsed_end
    end

    # Copy the rest of the fields
    @reservation.restaurant_id      = reservation_params[:restaurant_id]
    @reservation.party_size        = reservation_params[:party_size]
    @reservation.contact_name      = reservation_params[:contact_name]
    @reservation.contact_phone     = reservation_params[:contact_phone]
    @reservation.contact_email     = reservation_params[:contact_email]
    @reservation.deposit_amount    = reservation_params[:deposit_amount]
    @reservation.reservation_source = reservation_params[:reservation_source]
    @reservation.special_requests  = reservation_params[:special_requests]
    @reservation.status            = reservation_params[:status]

    # NEW: seat_preferences
    # If included in params, it's an array of arrays or array of strings
    @reservation.seat_preferences  = reservation_params[:seat_preferences] if reservation_params[:seat_preferences]

    # If current_user is staff/admin, fix the restaurant_id
    if current_user && current_user.role != 'super_admin'
      @reservation.restaurant_id = current_user.restaurant_id
    else
      # If user is anonymous or super_admin, default to #1 if none given
      @reservation.restaurant_id ||= 1
    end

    # Ensure there's a valid start_time
    unless @reservation.start_time
      return render json: { error: "start_time is required" }, status: :unprocessable_entity
    end

    # If no end_time given, default to start_time + 60 minutes
    @reservation.end_time ||= (@reservation.start_time + 60.minutes)

    # Capacity check
    restaurant = Restaurant.find(@reservation.restaurant_id)
    if exceeds_capacity?(restaurant, @reservation.start_time, @reservation.end_time, @reservation.party_size)
      return render json: { error: "Not enough seats for that timeslot" }, status: :unprocessable_entity
    end

    # Save if capacity is okay
    if @reservation.save
      # Example: send confirmation emails/texts
      if @reservation.contact_email.present?
        ReservationMailer.booking_confirmation(@reservation).deliver_later
      end

      if @reservation.contact_phone.present?
        message_body = <<~MSG.squish
          Hi #{@reservation.contact_name}, your Rotary Sushi reservation is confirmed
          on #{@reservation.start_time.strftime("%B %d at %I:%M %p")}.
          We look forward to seeing you!
        MSG
        ClicksendClient.send_text_message(
          to:   @reservation.contact_phone,
          body: message_body,
          from: 'RotarySushi'
        )
      end

      render json: @reservation, status: :created
    else
      render json: { errors: @reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])

    # We'll handle seat_preferences separately or allow the strong params to do so
    if reservation.update(reservation_params)
      render json: reservation
    else
      render json: { errors: reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])
    reservation.destroy
    head :no_content
  end

  private

  def reservation_params
    # The key addition: seat_preferences: [] to permit arrays
    params.require(:reservation).permit(
      :restaurant_id,
      :start_time,
      :end_time,
      :party_size,
      :contact_name,
      :contact_phone,
      :contact_email,
      :deposit_amount,
      :reservation_source,
      :special_requests,
      :status,
      seat_preferences: []
    )
  end

  # Returns true if adding `new_party_size` at [start_dt..end_dt)
  # would exceed the restaurant’s seat capacity.
  def exceeds_capacity?(restaurant, start_dt, end_dt, new_party_size)
    total_seats = restaurant.current_seats.count
    return true if total_seats.zero?

    overlapping = restaurant
                    .reservations
                    .where.not(status: %w[canceled finished no_show])
                    .where("start_time < ? AND end_time > ?", end_dt, start_dt)

    already_booked = overlapping.sum(:party_size)
    (already_booked + new_party_size) > total_seats
  end
end
