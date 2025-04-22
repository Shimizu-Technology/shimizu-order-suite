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
        restaurant.timezone_offset
      )
      
      # Get the restaurant's operating hours for this day
      day_of_week_num = date_obj.wday # 0 = Sunday, 1 = Monday, etc.
      operating_hour = scope_query(OperatingHour).find_by(day_of_week: day_of_week_num)
      
      # Check if the restaurant is open on this day
      if operating_hour.nil? || operating_hour.closed
        return { 
          success: true, 
          available: false, 
          reason: "Restaurant is closed on this day" 
        }
      end
      
      # Check if the requested time is within operating hours
      opening_time = operating_hour.open_time
      closing_time = operating_hour.close_time
      
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
      total_seats = restaurant.current_seats.count
      
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
        .where("start_time >= ? AND start_time <= ?", 
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
      day_of_week_num = date_obj.wday # 0 = Sunday, 1 = Monday, etc.
      operating_hour = scope_query(OperatingHour).find_by(day_of_week: day_of_week_num)
      
      # Check if the restaurant is open on this day
      if operating_hour.nil? || operating_hour.closed
        return { 
          success: true, 
          available_slots: [], 
          message: "Restaurant is closed on this day" 
        }
      end
      
      # Get opening and closing times
      opening_time = operating_hour.open_time
      closing_time = operating_hour.close_time
      
      # Generate time slots at 30-minute intervals
      time_slots = []
      
      # Convert date_obj and times to a proper datetime for comparison
      current_date = date_obj.to_time
      
      # Create datetime objects for opening and closing times on the selected date
      start_datetime = Time.new(
        current_date.year, 
        current_date.month, 
        current_date.day, 
        opening_time.hour, 
        opening_time.min
      )
      
      end_datetime = Time.new(
        current_date.year, 
        current_date.month, 
        current_date.day, 
        closing_time.hour, 
        closing_time.min
      )
      
      # Generate slots at 30-minute intervals
      current_slot = start_datetime
      
      while current_slot <= end_datetime - 30.minutes # Don't allow reservations at closing time
        time_slots << current_slot.strftime('%H:%M')
        current_slot += 30.minutes
      end
      
      # Log the generated time slots for debugging
      Rails.logger.debug "Generated #{time_slots.length} time slots for #{date}: #{time_slots.inspect}"
      
      # For now, consider all time slots as available since we're just restoring functionality
      # Later we can implement more sophisticated availability checking
      available_slots = time_slots.map do |time_slot|
        {
          time: time_slot,
          available_seats: 100 # Placeholder value
        }
      end
      
      # Log the available slots for debugging
      Rails.logger.debug "Found #{available_slots.length} available slots for #{date}"
      
      { success: true, available_slots: available_slots }
    rescue => e
      { success: false, errors: ["Failed to get available time slots: #{e.message}"], status: :internal_server_error }
    end
  end

  # Get the restaurant's operating hours
  def get_operating_hours
    operating_hours = {}
    
    # Get operating hours from the database
    db_hours = scope_query(OperatingHour).order(:day_of_week)
    
    # Map day numbers to day names
    day_names = %w[sunday monday tuesday wednesday thursday friday saturday]
    
    # Ensure all days of the week are present
    day_names.each_with_index do |day, index|
      hour = db_hours.find { |h| h.day_of_week == index }
      
      if hour
        operating_hours[day] = {
          'is_open' => !hour.closed,
          'opening_time' => hour.open_time.strftime('%H:%M'),
          'closing_time' => hour.close_time.strftime('%H:%M')
        }
      else
        operating_hours[day] = {
          'is_open' => false,
          'opening_time' => '09:00',
          'closing_time' => '17:00'
        }
      end
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
      
      # Map day names to day numbers
      day_mapping = {
        'sunday' => 0,
        'monday' => 1,
        'tuesday' => 2,
        'wednesday' => 3,
        'thursday' => 4,
        'friday' => 5,
        'saturday' => 6
      }
      
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
      
      # Update the operating hours in the database
      ActiveRecord::Base.transaction do
        # Map day names to day numbers
        day_mapping = {
          'sunday' => 0,
          'monday' => 1,
          'tuesday' => 2,
          'wednesday' => 3,
          'thursday' => 4,
          'friday' => 5,
          'saturday' => 6
        }
        
        hours_params.each do |day, day_hours|
          day_num = day_mapping[day]
          next unless day_num
          
          # Find or create the operating hour record
          hour = scope_query(OperatingHour).find_or_initialize_by(day_of_week: day_num)
          
          # Update the record
          hour.closed = !day_hours['is_open']
          hour.open_time = Time.parse(day_hours['opening_time'])
          hour.close_time = Time.parse(day_hours['closing_time'])
          hour.save!
        end
      end
      
      # Return the updated operating hours
      { success: true, operating_hours: get_operating_hours[:operating_hours] }
    rescue => e
      { success: false, errors: ["Failed to update operating hours: #{e.message}"], status: :internal_server_error }
    end
  end
end
