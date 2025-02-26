# app/controllers/availability_controller.rb

class AvailabilityController < ApplicationController
  before_action :optional_authorize
  
  # Mark this as a public endpoint that doesn't require restaurant context
  def public_endpoint?
    true
  end
  # GET /availability?date=YYYY-MM-DD&party_size=4&restaurant_id=1
  def index
    date_str   = params[:date]
    party_size = params[:party_size].to_i
    
    # Get restaurant from current context or from params
    restaurant = if @current_restaurant
                   @current_restaurant
                 elsif params[:restaurant_id].present?
                   Restaurant.find_by(id: params[:restaurant_id])
                 else
                   render json: { error: "Restaurant ID is required" }, status: :unprocessable_entity
                   return
                 end

    # 1) Generate local timeslots for that date
    slots = generate_timeslots_for_date(restaurant, date_str)

    # 2) For each slot => check capacity in can_accommodate?
    average_dining_duration = restaurant.default_reservation_length.minutes
    available_slots = []

    slots.each do |slot|
      slot_end = slot + average_dining_duration
      if can_accommodate?(restaurant, party_size, slot, slot_end)
        available_slots << slot
      end
    end

    # Return them in HH:MM format
    render json: {
      slots: available_slots.map { |ts| ts.strftime("%H:%M") }
    }
  end

  private

  def generate_timeslots_for_date(restaurant, date_str)
    return [] if date_str.blank?
    return [] unless restaurant.time_zone.present?

    Time.use_zone(restaurant.time_zone) do
      local_date = Time.zone.parse(date_str) # => e.g. 2025-02-10 00:00
      return [] unless local_date

      wday = local_date.wday
      oh = OperatingHour.find_by(restaurant_id: restaurant.id, day_of_week: wday)
      # If no OperatingHour or it’s closed => no slots
      return [] if oh.nil? || oh.closed?

      base_open  = local_date.change(hour: oh.open_time.hour,  min: oh.open_time.min)
      base_close = local_date.change(hour: oh.close_time.hour, min: oh.close_time.min)

      # Check if there's a SpecialEvent for this date
      event = SpecialEvent.find_by(restaurant_id: restaurant.id, event_date: local_date.to_date)

      # 1) If event is fully closed => no slots
      return [] if event&.closed?

      # 2) If event.exclusive_booking => maybe just 1 big slot at base_open
      if event&.exclusive_booking
        # Return single slot => [ 09:00 for example ]
        return [base_open]
      end

      # 3) If event.start_time + event.end_time exist => clamp open/close times
      if event&.start_time.present? && event&.end_time.present?
        # This is a partial day event. We'll generate normal increments but only in [event.start_time..event.end_time]
        event_start = local_date.change(hour: event.start_time.hour, min: event.start_time.min)
        event_end   = local_date.change(hour: event.end_time.hour,   min: event.end_time.min)

        base_open  = [base_open,  event_start].max
        base_close = [base_close, event_end].min
        return [] if base_close <= base_open
      end

      # 4) If the event wants exactly ONE slot at event.start_time => e.g. 09:00
      #    We can do a check for "special_event indicates single_time_only"
      #    or if event.start_time is present but you want only that slot.
      #    For example:
      if event && event.start_time.present? && event.end_time.blank?
        # user says => only show one timeslot => event.start_time
        single_slot = local_date.change(
          hour: event.start_time.hour,
          min:  event.start_time.min
        )
        return [single_slot] # just one slot
      end

      # If no special logic => build normal half-hour increments
      interval = restaurant.time_slot_interval || 30
      slots = []
      current_slot = base_open
      while current_slot < base_close
        slots << current_slot
        current_slot += interval.minutes
      end
      slots
    end
  end

  def can_accommodate?(restaurant, party_size, start_dt, end_dt)
    total_seats = restaurant.current_seats.count
    return false if total_seats.zero?

    event = SpecialEvent.find_by(
      restaurant_id: restaurant.id,
      event_date:    start_dt.to_date
    )

    # If day is closed => block
    return false if event&.closed?

    # If exclusive => block if any existing reservation is on that day
    if event&.exclusive_booking
      day_start = start_dt.beginning_of_day
      day_end   = start_dt.end_of_day
      existing = restaurant.reservations
        .where.not(status: %w[canceled finished no_show])
        .where("start_time < ? AND end_time > ?", day_end, day_start)
      return existing.empty?
    end

    # If there's a max_capacity => ensure we don't exceed it
    if event&.max_capacity&.positive?
      day_start = start_dt.beginning_of_day
      day_end   = start_dt.end_of_day
      day_reservations = restaurant.reservations
        .where.not(status: %w[canceled finished no_show])
        .where("start_time < ? AND end_time > ?", day_end, day_start)
      used = day_reservations.sum(:party_size)
      return false if (used + party_size) > event.max_capacity
    end

    # Normal seat overlap logic
    overlapping = restaurant.reservations
      .where.not(status: %w[canceled finished no_show])
      .where("start_time < ? AND end_time > ?", end_dt, start_dt)
    already_booked = overlapping.sum(:party_size)
    (already_booked + party_size) <= total_seats
  end
end
