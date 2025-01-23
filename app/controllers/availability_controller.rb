# app/controllers/availability_controller.rb

class AvailabilityController < ApplicationController
  # GET /availability?date=YYYY-MM-DD&party_size=4
  def index
    date_str   = params[:date]
    party_size = params[:party_size].to_i

    # For simplicity we do a single restaurant find(1). If your staff is always from
    # the same restaurant, that's fine. Otherwise you might do current_user.restaurant.
    restaurant = Restaurant.find(1)

    # 1) Generate local timeslots for that date
    slots = generate_timeslots_for_date(restaurant, date_str)

    # 2) For each slot => slot + 60min, check capacity
    average_dining_duration = 60.minutes
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

  # Generate timeslots from opening_time..closing_time in the restaurant’s time_zone
  def generate_timeslots_for_date(restaurant, date_str)
    return [] if date_str.blank?
    return [] unless restaurant.time_zone.present?

    # user might pass "2025-01-21"
    # interpret as 2025-01-21 00:00:00 in restaurant.time_zone
    Time.use_zone(restaurant.time_zone) do
      local_date_start = Time.zone.parse(date_str)
      return [] unless local_date_start

      open_time  = restaurant.opening_time  # e.g. "17:00"
      close_time = restaurant.closing_time  # e.g. "21:00"
      interval   = restaurant.time_slot_interval || 30

      # Build day-based local Time objects
      base_open = Time.zone.local(
        local_date_start.year,
        local_date_start.month,
        local_date_start.day,
        open_time.hour,
        open_time.min
      )

      base_close = Time.zone.local(
        local_date_start.year,
        local_date_start.month,
        local_date_start.day,
        close_time.hour,
        close_time.min
      )

      slots = []
      current_slot = base_open
      while current_slot < base_close
        slots << current_slot
        current_slot += interval.minutes
      end
      slots
    end
  end

  # Basic capacity check (total seats minus overlapping reservations)
  def can_accommodate?(restaurant, party_size, start_dt, end_dt)
    total_seats = restaurant.current_seats.count
    return false if total_seats.zero?

    overlapping = restaurant
      .reservations
      .where.not(status: %w[canceled finished no_show])
      .where("start_time < ? AND end_time > ?", end_dt, start_dt)

    already_booked = overlapping.sum(:party_size)
    (already_booked + party_size) <= total_seats
  end
end
