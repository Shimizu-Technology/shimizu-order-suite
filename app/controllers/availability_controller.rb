# app/controllers/availability_controller.rb

class AvailabilityController < ApplicationController
  # GET /availability?date=YYYY-MM-DD&party_size=4
  def index
    date_str   = params[:date]
    party_size = params[:party_size].to_i

    # For simplicity => Restaurant.find(1). In a multi-tenant scenario, you'd use current_user.restaurant
    restaurant = Restaurant.find(1)

    # 1) Generate local timeslots for that date
    slots = generate_timeslots_for_date(restaurant, date_str)

    # 2) For each slot => slot + average_dining_duration
    #   (We can use restaurant.default_reservation_length or just 60 minutes)
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

  # Generate timeslots from OperatingHour + SpecialEvent in the restaurant’s time_zone
  def generate_timeslots_for_date(restaurant, date_str)
    return [] if date_str.blank?
    return [] unless restaurant.time_zone.present?

    # e.g. "2025-01-21" => interpret as midnight that day in the restaurant's tz
    Time.use_zone(restaurant.time_zone) do
      local_date_start = Time.zone.parse(date_str) # => 2025-01-21 00:00
      return [] unless local_date_start

      wday = local_date_start.wday # 0=Sunday..6=Saturday
      oh = OperatingHour.find_by(restaurant_id: restaurant.id, day_of_week: wday)
      # If there's no OperatingHour or it's closed => no slots
      return [] if oh.nil? || oh.closed?

      base_open = local_date_start.change(hour: oh.open_time.hour, min: oh.open_time.min)
      base_close = local_date_start.change(hour: oh.close_time.hour, min: oh.close_time.min)

      # Next check if there's a SpecialEvent for this date
      special_event = SpecialEvent.find_by(restaurant_id: restaurant.id, event_date: local_date_start.to_date)
      if special_event
        if special_event.exclusive_booking
          # Option A: Return only one big "slot" => e.g. base_open as the "start time"
          # Or Option B: return [] if the day is fully booked in some other logic
          # We'll do Option A for demonstration:
          return [base_open]
        elsif special_event.max_capacity.positive?
          # We still build normal timeslots. We'll handle capacity in can_accommodate?
          # or do more advanced logic. For simplicity, proceed.
        end
      end

      # Build timeslots by restaurant.time_slot_interval (or oh-specific interval if you prefer)
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

  # Basic capacity check (total seats minus overlapping reservations)
  def can_accommodate?(restaurant, party_size, start_dt, end_dt)
    total_seats = restaurant.current_seats.count
    return false if total_seats.zero?

    # If there's a special event with exclusive_booking, you might skip logic or allow only if no existing reservations
    # We'll do a minimal example:
    event = SpecialEvent.find_by(restaurant_id: restaurant.id, event_date: start_dt.to_date)
    if event&.exclusive_booking
      # If there's ANY reservation that day, block
      day_start = start_dt.beginning_of_day
      day_end   = start_dt.end_of_day
      existing = restaurant.reservations.where.not(status: %w[canceled finished no_show])
        .where("start_time < ? AND end_time > ?", day_end, day_start)
      return existing.empty?
    end

    # If there's a max_capacity, check if total seats used that day >= max_capacity
    if event&.max_capacity&.positive?
      day_start = start_dt.beginning_of_day
      day_end   = start_dt.end_of_day
      day_reservations = restaurant.reservations
        .where.not(status: %w[canceled finished no_show])
        .where("start_time < ? AND end_time > ?", day_end, day_start)
      used = day_reservations.sum(:party_size)
      if (used + party_size) > event.max_capacity
        return false
      end
    end

    # Normal seat overlap logic
    overlapping = restaurant
      .reservations
      .where.not(status: %w[canceled finished no_show])
      .where("start_time < ? AND end_time > ?", end_dt, start_dt)

    already_booked = overlapping.sum(:party_size)
    (already_booked + party_size) <= total_seats
  end
end
