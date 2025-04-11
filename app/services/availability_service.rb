# app/services/availability_service.rb
class AvailabilityService < TenantScopedService
  attr_accessor :current_user

  # Check availability for a given date, time, and party size
  def check_availability(date, time, party_size)
    # Convert date and time to a datetime object
    begin
      date_obj = Date.parse(date)
      time_obj = Time.parse(time)
      
      # Combine date and time
      datetime = Time.new(
        date_obj.year, 
        date_obj.month, 
        date_obj.day, 
        time_obj.hour, 
        time_obj.min, 
        time_obj.sec, 
        current_restaurant.timezone_offset
      )
      
      # Get the restaurant's operating hours for this day
      day_of_week = date_obj.strftime('%A').downcase
      operating_hours = current_restaurant.operating_hours&.dig(day_of_week)
      
      # Check if the restaurant is open on this day
      if operating_hours.blank? || !operating_hours['is_open']
        return { 
          success: true, 
          available: false, 
          reason: "Restaurant is closed on this day" 
        }
      end
      
      # Check if the requested time is within operating hours
      opening_time = Time.parse(operating_hours['opening_time'])
      closing_time = Time.parse(operating_hours['closing_time'])
      
      if time_obj < opening_time || time_obj > closing_time
        return { 
          success: true, 
          available: false, 
          reason: "Restaurant is closed at this time" 
        }
      end
      
      # Check if there are any special events that might affect availability
      special_event = scope_query(SpecialEvent).find_by(
        "event_date = ? AND event_start_time <= ? AND event_end_time >= ?",
        date_obj, time_obj, time_obj
      )
      
      if special_event && special_event.affects_availability
        return { 
          success: true, 
          available: false, 
          reason: "Special event: #{special_event.name}" 
        }
      end
      
      # Check if there are enough available seats
      total_seats = current_restaurant.current_seats.count
      
      # If no seats are configured, return an error
      if total_seats.zero?
        return { 
          success: false, 
          errors: ["No seats configured for this restaurant"], 
          status: :unprocessable_entity 
        }
      end
      
      # Find overlapping reservations
      overlapping_reservations = scope_query(Reservation)
        .where.not(status: %w[canceled finished no_show])
        .where("reservation_date >= ? AND reservation_date <= ?", 
               datetime - 2.hours, 
               datetime + 2.hours)
      
      # Calculate total seats taken by existing reservations
      seats_taken = overlapping_reservations.sum(:party_size)
      
      # Check if there are enough seats available
      available = (seats_taken + party_size.to_i) <= total_seats
      
      if available
        { 
          success: true, 
          available: true, 
          available_seats: total_seats - seats_taken,
          total_seats: total_seats
        }
      else
        { 
          success: true, 
          available: false, 
          reason: "Not enough seats available",
          available_seats: total_seats - seats_taken,
          total_seats: total_seats
        }
      end
    rescue => e
      { success: false, errors: ["Failed to check availability: #{e.message}"], status: :internal_server_error }
    end
  end

  # Get available time slots for a given date and party size
  def available_time_slots(date, party_size)
    begin
      date_obj = Date.parse(date)
      
      # Get the restaurant's operating hours for this day
      day_of_week = date_obj.strftime('%A').downcase
      operating_hours = current_restaurant.operating_hours&.dig(day_of_week)
      
      # Check if the restaurant is open on this day
      if operating_hours.blank? || !operating_hours['is_open']
        return { 
          success: true, 
          available_slots: [], 
          message: "Restaurant is closed on this day" 
        }
      end
      
      # Get opening and closing times
      opening_time = Time.parse(operating_hours['opening_time'])
      closing_time = Time.parse(operating_hours['closing_time'])
      
      # Generate time slots at 30-minute intervals
      time_slots = []
      current_time = opening_time
      
      while current_time <= closing_time
        time_slots << current_time.strftime('%H:%M')
        current_time += 30.minutes
      end
      
      # Check availability for each time slot
      available_slots = []
      
      time_slots.each do |time_slot|
        result = check_availability(date, time_slot, party_size)
        if result[:success] && result[:available]
          available_slots << {
            time: time_slot,
            available_seats: result[:available_seats]
          }
        end
      end
      
      { success: true, available_slots: available_slots }
    rescue => e
      { success: false, errors: ["Failed to get available time slots: #{e.message}"], status: :internal_server_error }
    end
  end

  # Get the restaurant's operating hours
  def get_operating_hours
    operating_hours = current_restaurant.operating_hours || {}
    
    # Ensure all days of the week are present
    %w[monday tuesday wednesday thursday friday saturday sunday].each do |day|
      operating_hours[day] ||= {
        'is_open' => false,
        'opening_time' => '09:00',
        'closing_time' => '17:00'
      }
    end
    
    { success: true, operating_hours: operating_hours }
  rescue => e
    { success: false, errors: ["Failed to get operating hours: #{e.message}"], status: :internal_server_error }
  end

  # Update the restaurant's operating hours
  def update_operating_hours(hours_params)
    begin
      # Validate the hours_params format
      unless hours_params.is_a?(Hash)
        return { 
          success: false, 
          errors: ["Invalid operating hours format"], 
          status: :unprocessable_entity 
        }
      end
      
      # Ensure all required days are present
      %w[monday tuesday wednesday thursday friday saturday sunday].each do |day|
        unless hours_params.key?(day)
          return { 
            success: false, 
            errors: ["Missing operating hours for #{day}"], 
            status: :unprocessable_entity 
          }
        end
        
        day_hours = hours_params[day]
        
        # Validate day hours format
        unless day_hours.is_a?(Hash) && 
               day_hours.key?('is_open') && 
               day_hours.key?('opening_time') && 
               day_hours.key?('closing_time')
          return { 
            success: false, 
            errors: ["Invalid format for #{day} operating hours"], 
            status: :unprocessable_entity 
          }
        end
        
        # Validate time formats
        begin
          Time.parse(day_hours['opening_time']) if day_hours['is_open']
          Time.parse(day_hours['closing_time']) if day_hours['is_open']
        rescue
          return { 
            success: false, 
            errors: ["Invalid time format for #{day}"], 
            status: :unprocessable_entity 
          }
        end
      end
      
      # Update the operating hours
      current_restaurant.update(operating_hours: hours_params)
      
      { success: true, operating_hours: current_restaurant.operating_hours }
    rescue => e
      { success: false, errors: ["Failed to update operating hours: #{e.message}"], status: :internal_server_error }
    end
  end
end
