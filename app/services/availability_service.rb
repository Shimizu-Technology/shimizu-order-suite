# app/services/availability_service.rb
class AvailabilityService < TenantScopedService
  attr_accessor :current_user

  # Validate tenant context before processing any requests
  def validate_tenant_context
    unless restaurant.present?
      Rails.logger.error "TENANT ISOLATION: No restaurant context found in AvailabilityService"
      raise TenantIsolationError, "Restaurant context is required for reservation operations"
    end
    
    Rails.logger.info "TENANT ISOLATION: Validated restaurant context (id: #{restaurant.id})"
    true
  end

  # Check availability for a given date, time, and party size
  def check_availability(date, time, party_size, location_id = nil)
    # Validate tenant context first
    validate_tenant_context
    
    # Convert date and time to a datetime object
    Rails.logger.info "AVAILABILITY CHECK: Checking date=#{date}, time=#{time}, party_size=#{party_size}, location_id=#{location_id}"
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
      
      # Check if there are any blocked periods that affect this time
      blocked_period_query = scope_query(BlockedPeriod).active
                                .where('start_time <= ? AND end_time >= ?', datetime, datetime)
      
      # Add location-specific filter if provided
      if location_id.present?
        blocked_period_query = blocked_period_query.where('location_id IS NULL OR location_id = ?', location_id)
      else
        blocked_period_query = blocked_period_query.where('location_id IS NULL')
      end
      
      blocked_period = blocked_period_query.first
      
      if blocked_period.present?
        return {
          success: true,
          available: false,
          reason: "Time is blocked: #{blocked_period.reason}"
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
      
      # Get configurable parameters from restaurant settings
      max_party_size = restaurant.max_party_size
      Rails.logger.info "AVAILABILITY CHECK: Restaurant max party size is #{max_party_size}"
      
      # Check if party size exceeds restaurant maximum
      if party_size.to_i > max_party_size
        return {
          success: true,
          available: false,
          reason: "Party size exceeds restaurant maximum of #{max_party_size}",
          max_party_size: max_party_size
        }
      end
      
      # Calculate total capacity
      begin
        # Get seats from the restaurant, using location-specific seats if location_id is provided
        if location_id.present?
          seats = restaurant.location_seats(location_id) rescue []
          Rails.logger.info "AVAILABILITY: Using location-specific layout for location_id=#{location_id}"
        else
          seats = restaurant.current_seats rescue []
        end
        
        # Calculate total capacity safely
        total_seats = 0
        
        if seats.present?
          # Try to sum the capacities of all seats
          seats.each do |seat|
            if seat.respond_to?(:capacity) && seat.capacity.present? && seat.capacity.to_i > 0
              total_seats += seat.capacity.to_i
            else
              # If a seat has no capacity, assume 1
              total_seats += 1
            end
          end
        end
        
        # If no seats or zero capacity, use default values or restaurant setting
        if total_seats.zero?
          # Try to get capacity from restaurant settings
          if restaurant.respond_to?(:admin_settings) && 
             restaurant.admin_settings.present? && 
             restaurant.admin_settings[:seating_capacity].present?
            total_seats = restaurant.admin_settings[:seating_capacity].to_i
          else
            # Default to 26 seats as a fallback
            total_seats = 26
          end
        end
      rescue => e
        Rails.logger.error "AVAILABILITY CHECK: Error calculating capacity: #{e.message}"
        # Use a safe default
        total_seats = 26
      end
      
      Rails.logger.info "AVAILABILITY CHECK: Total seat capacity is #{total_seats}"
      
      # Get configurable overlap window from restaurant settings
      overlap_window_minutes = restaurant.reservation_overlap_window
      reservation_duration = restaurant.reservation_duration
      turnaround_time = restaurant.turnaround_time
      
      Rails.logger.info "AVAILABILITY CHECK: Using overlap window of #{overlap_window_minutes} minutes"
      Rails.logger.info "AVAILABILITY CHECK: Using reservation duration of #{reservation_duration} minutes"
      Rails.logger.info "AVAILABILITY CHECK: Using turnaround time of #{turnaround_time} minutes"
      
      # Find overlapping reservations using configurable overlap window
      overlapping_reservations = scope_query(Reservation)
        .where.not(status: %w[canceled finished no_show])
        .where("start_time >= ? AND start_time <= ?", 
               datetime - overlap_window_minutes.minutes, 
               datetime + overlap_window_minutes.minutes)
               
      # Filter by location if provided
      if location_id.present?
        overlapping_reservations = overlapping_reservations.where(location_id: location_id)
        Rails.logger.info "AVAILABILITY CHECK: Filtering by location_id=#{location_id}"
      end
      
      # Calculate total seats taken by existing reservations, taking into account
      # each reservation's specific start time, duration, and our desired turnaround time
      seats_taken = 0
      begin
        overlapping_reservations.each do |res|
          # Get this reservation's duration (or use the restaurant's default if not set)
          res_duration = res.duration_minutes || reservation_duration
          
          # Calculate the actual end time of this reservation including turnaround time
          res_end_time = res.start_time + res_duration.minutes + turnaround_time.minutes
          
          # Check if this reservation overlaps with our current time slot's effective window
          slot_start_time = datetime
          slot_end_time = datetime + reservation_duration.minutes
          
          if (res.start_time <= slot_end_time && res_end_time >= slot_start_time)
            # This reservation overlaps with our desired time slot
            seats_taken += res.party_size.to_i
            Rails.logger.debug "AVAILABILITY CHECK: Reservation #{res.id} overlaps, adding #{res.party_size} seats"
          end
          
          # is_blocked is determined later, no need to check here
        end
      rescue => e
        Rails.logger.error "AVAILABILITY CHECK: Error in precise overlap calculation: #{e.message}. Falling back to simpler approach."
        seats_taken = overlapping_reservations.sum(:party_size)
      end
      
      Rails.logger.info "AVAILABILITY CHECK: Total seats taken: #{seats_taken}"
      
      # Check if there are enough seats available
      available_seats = total_seats - seats_taken
      available = (available_seats >= party_size.to_i)
      
      if available
        { 
          success: true, 
          available: true, 
          available_seats: available_seats,
          total_seats: total_seats,
          max_party_size: max_party_size
        }
      else
        { 
          success: true, 
          available: false, 
          reason: "Not enough seats available",
          available_seats: available_seats,
          total_seats: total_seats,
          max_party_size: max_party_size
        }
      end
    rescue => e
      { success: false, errors: ["Failed to check availability: #{e.message}"], status: :internal_server_error }
    end
  end

  # Get available time slots for a given date and party size
  # location_id: Optional parameter to filter availability by location
  def available_time_slots(date, party_size, location_id = nil)
    # Validate tenant context first
    validate_tenant_context
    
    begin
      Rails.logger.info "AVAILABILITY: Calculating available time slots for date=#{date}, party_size=#{party_size}, location_id=#{location_id}"
      date_obj = Date.parse(date)
      
      # Get the restaurant's operating hours for this day
      day_of_week_num = date_obj.wday # 0 = Sunday, 1 = Monday, etc.
      operating_hour = scope_query(OperatingHour).find_by(day_of_week: day_of_week_num)
      
      # Check if the restaurant is open on this day
      if operating_hour.nil? || operating_hour.closed
        Rails.logger.info "AVAILABILITY: Restaurant is closed on day #{day_of_week_num}"
        return { 
          success: true, 
          available_slots: [], 
          message: "Restaurant is closed on this day" 
        }
      end
      
      # Get opening and closing times
      opening_time = operating_hour.open_time
      closing_time = operating_hour.close_time
      
      # Get configurable parameters from restaurant settings
      interval_minutes = restaurant.reservation_time_slot_interval
      max_party_size = restaurant.max_party_size
      Rails.logger.info "AVAILABILITY: Using time slot interval of #{interval_minutes} minutes from restaurant settings"
      Rails.logger.info "AVAILABILITY: Restaurant max party size is #{max_party_size}"
      
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
      
      # Generate slots at configurable intervals
      current_slot = start_datetime
      
      # Don't allow reservations at closing time, leave at least 1 interval before closing
      while current_slot <= end_datetime - interval_minutes.minutes
        time_slots << current_slot.strftime('%H:%M')
        current_slot += interval_minutes.minutes
      end
      
      # Log the generated time slots for debugging
      Rails.logger.debug "Generated #{time_slots.length} time slots for #{date}: #{time_slots.inspect}"
      
      # Get all blocked periods for this date to check against each time slot
      blocked_periods_query = scope_query(BlockedPeriod).active
                                .where('DATE(start_time) <= ? AND DATE(end_time) >= ?', date_obj, date_obj)
      
      # Add location-specific filter if provided
      if location_id.present?
        # Include both location-specific blocks and restaurant-wide blocks (NULL location)
        blocked_periods_query = blocked_periods_query.where('location_id IS NULL OR location_id = ?', location_id)
      else
        # If no location specified, only consider restaurant-wide blocks
        blocked_periods_query = blocked_periods_query.where('location_id IS NULL')
      end
      
      blocked_periods = blocked_periods_query.to_a
      Rails.logger.info "AVAILABILITY: Found #{blocked_periods.length} blocked periods for #{date}"
      
      # Log each blocked period for debugging
      blocked_periods.each do |period|
        Rails.logger.debug "AVAILABILITY: Blocked period #{period.id}: #{period.start_time} to #{period.end_time} - #{period.reason}"
      end
      
      # Check each time slot for actual availability based on existing reservations
      available_slots = []
      
      # Determine total seating capacity safely
      begin
        # Get seats from the restaurant, using location-specific seats if location_id is provided
        if location_id.present?
          seats = restaurant.location_seats(location_id) rescue []
          Rails.logger.info "AVAILABILITY: Using location-specific layout for location_id=#{location_id}"
        else
          seats = restaurant.current_seats rescue []
        end
        Rails.logger.info "AVAILABILITY: Found #{seats.length} seats for restaurant"
        
        # Calculate total capacity safely
        total_seats = 0
        
        if seats.present?
          # Try to sum the capacities of all seats
          seats.each do |seat|
            if seat.respond_to?(:capacity) && seat.capacity.present? && seat.capacity.to_i > 0
              total_seats += seat.capacity.to_i
            else
              # If a seat has no capacity, assume 1
              total_seats += 1
            end
          end
          Rails.logger.info "AVAILABILITY: Calculated total seat capacity: #{total_seats}"
        end
        
        # If no seats or zero capacity, use default values
        if total_seats.zero?
          # Try to get capacity from restaurant settings
          if restaurant.respond_to?(:admin_settings) && 
             restaurant.admin_settings.present? && 
             restaurant.admin_settings[:seating_capacity].present?
            total_seats = restaurant.admin_settings[:seating_capacity].to_i
            Rails.logger.info "AVAILABILITY: Using seating_capacity from admin_settings: #{total_seats}"
          else
            # Default to 26 seats as specified
            total_seats = 26
            Rails.logger.info "AVAILABILITY: Using default capacity of #{total_seats} seats"
          end
        end
      rescue => e
        # If anything fails, use a safe default
        total_seats = 26
        Rails.logger.error "AVAILABILITY: Error calculating seat capacity: #{e.message}. Using default of #{total_seats}"
        Rails.logger.error e.backtrace.join("\n")
      end
      
      time_slots.each do |time_slot|
        begin
          # Create a datetime for this slot
          time_obj = Time.parse(time_slot)
          # Create a datetime using the restaurant's timezone if available, or default to the current timezone
          begin
            if restaurant.respond_to?(:time_zone) && restaurant.time_zone.present?
              # Use the restaurant's time_zone with ActiveSupport's TimeZone
              zone = ActiveSupport::TimeZone[restaurant.time_zone] rescue nil
              
              if zone
                # If we have a valid zone, create the datetime in that zone
                datetime = zone.local(current_date.year, current_date.month, current_date.day, 
                                     time_obj.hour, time_obj.min, 0)
              else
                # Fallback to local time if the timezone is invalid
                datetime = Time.new(current_date.year, current_date.month, current_date.day, 
                                   time_obj.hour, time_obj.min, 0)
              end
            else
              # No timezone specified, use local time
              datetime = Time.new(current_date.year, current_date.month, current_date.day, 
                                 time_obj.hour, time_obj.min, 0)
            end
          rescue => e
            # Handle any timezone conversion errors, default to local time
            Rails.logger.error "AVAILABILITY: Error with timezone conversion: #{e.message}"
            datetime = Time.new(current_date.year, current_date.month, current_date.day, 
                               time_obj.hour, time_obj.min, 0)
          end
          
          Rails.logger.info "AVAILABILITY: Checking timeslot #{time_slot} for party size #{party_size}"
          
          # Get configurable overlap window from restaurant settings
          overlap_window_minutes = restaurant.reservation_overlap_window
          reservation_duration = restaurant.reservation_duration
          turnaround_time = restaurant.turnaround_time
          
          Rails.logger.info "AVAILABILITY: Using overlap window of #{overlap_window_minutes} minutes, reservation duration of #{reservation_duration} minutes, and turnaround time of #{turnaround_time} minutes"
          
          # Find overlapping reservations using configurable overlap window
          overlapping_reservations = []
          begin
            # Base query for overlapping reservations
            overlapping_reservations = scope_query(Reservation)
              .where.not(status: %w[canceled finished no_show])
              .where("start_time >= ? AND start_time <= ?", 
                     datetime - overlap_window_minutes.minutes, 
                     datetime + overlap_window_minutes.minutes)
            
            # Filter by location if provided
            if location_id.present?
              overlapping_reservations = overlapping_reservations.where(location_id: location_id)
              Rails.logger.info "AVAILABILITY: Filtering overlapping reservations by location_id=#{location_id}"
            end
            
            Rails.logger.info "AVAILABILITY: Found #{overlapping_reservations.count} overlapping reservations for #{time_slot}"
          rescue => e
            Rails.logger.error "AVAILABILITY: Error finding overlapping reservations: #{e.message}"
            # Continue with empty reservations array
          end
          
          # Calculate total seats taken by existing reservations, taking into account
          # each reservation's specific start time, duration, and our desired turnaround time
          seats_taken = 0
          begin
            # More precise calculation that checks if reservations actually overlap with this time slot
            # considering reservation duration and turnaround time
            overlapping_reservations.each do |res|
              # Get this reservation's duration (or use the restaurant's default if not set)
              res_duration = res.duration_minutes || reservation_duration
              
              # Calculate the actual end time of this reservation including turnaround time
              res_end_time = res.start_time + res_duration.minutes + turnaround_time.minutes
              
              # Check if this reservation overlaps with our current time slot's effective window
              slot_start_time = datetime
              slot_end_time = datetime + reservation_duration.minutes
              
              if (res.start_time <= slot_end_time && res_end_time >= slot_start_time)
                # This reservation overlaps with our desired time slot
                seats_taken += res.party_size.to_i
                Rails.logger.debug "AVAILABILITY: Reservation #{res.id} overlaps, adding #{res.party_size} seats"
              end
            end
          rescue => e
            # If the precise calculation fails, fall back to the simpler approach
            Rails.logger.error "AVAILABILITY: Error in precise overlap calculation: #{e.message}. Falling back to simpler approach."
            seats_taken = overlapping_reservations.sum(&:party_size)
          end
          
          available_seats = total_seats - seats_taken
          Rails.logger.info "AVAILABILITY: Time slot #{time_slot} - Total seats: #{total_seats}, Taken: #{seats_taken}, Available: #{available_seats}, Needed: #{party_size}"
          
          # Only add this slot if it has enough seats for the requested party
          # Also check that requested party size doesn't exceed restaurant's max party size
          # and that the time slot is not blocked
          requested_size = party_size.to_i
          
          # Check if this time slot is within any blocked periods
          is_blocked = false
          blocked_periods.each do |period|
            # Calculate the slot's start and end times
            slot_start_time = datetime
            slot_end_time = datetime + reservation_duration.minutes
            
            # Check if this slot overlaps with the blocked period
            # A slot overlaps if any part of it falls within the blocked period
            if (slot_start_time < period.end_time && slot_end_time > period.start_time)
              is_blocked = true
              Rails.logger.info "AVAILABILITY: Time slot #{time_slot} is blocked by period #{period.id} (#{period.start_time.strftime('%H:%M')} - #{period.end_time.strftime('%H:%M')})"
              break
            else
              Rails.logger.debug "AVAILABILITY: Time slot #{time_slot} does not overlap with blocked period #{period.id}"
            end
          end
          
          if requested_size > max_party_size
            Rails.logger.info "AVAILABILITY: Requested party size #{requested_size} exceeds restaurant maximum of #{max_party_size}"
            # Don't add any slots if party size exceeds maximum
          elsif is_blocked
            Rails.logger.info "AVAILABILITY: Time slot #{time_slot} is blocked and unavailable"
            # Don't add slots that are blocked
          elsif available_seats >= requested_size
            available_slots << {
              time: time_slot,
              available_seats: available_seats,
              max_party_size: max_party_size
            }
          end
        rescue => e
          Rails.logger.error "AVAILABILITY: Error processing time slot #{time_slot}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          # Continue to next time slot
        end
      end
      
      # Log the available slots for debugging
      Rails.logger.info "AVAILABILITY: Found #{available_slots.length} available slots for #{date} with party size #{party_size}"
      
      # Check if party size exceeds restaurant maximum
      message = nil
      if party_size.to_i > max_party_size
        message = "Requested party size exceeds restaurant maximum of #{max_party_size}"
      end
      
      # Always return a successful response with the available slots we found
      # Even if we had errors with some time slots, we can still return partial results
      response = { success: true, available_slots: available_slots }
      response[:message] = message if message
      response[:max_party_size] = max_party_size
      
      response
    rescue => e
      # Log the error
      Rails.logger.error "AVAILABILITY: Fatal error in available_time_slots: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return an empty array of slots rather than an error
      # This lets the UI still function even if we have backend issues
      { 
        success: true, 
        available_slots: [], 
        message: "No available time slots found" 
      }
    end
  end

  # Get the restaurant's operating hours
  # Calculate maximum available party size for a given date and time
  def max_party_size(date_str, time_str, location_id = nil, party_size = 2)
    # Validate tenant context first
    validate_tenant_context
    
    begin
      # Validate date and time
      if date_str.blank? || time_str.blank?
        return { 
          success: false, 
          errors: ["Date and time are required"],
          status: :unprocessable_entity 
        }
      end
      
      # Parse date and time safely
      begin
        Rails.logger.info "Parsing date: #{date_str} and time: #{time_str}"
        date_obj = Date.parse(date_str) rescue Date.today
        
        # Extract just the time portion without the date
        # Format expected: "HH:MM" or "H:MM" (e.g., "14:30" or "2:30")
        hour, minute = time_str.split(':').map(&:to_i)
        
        # Create a datetime object for the start time using the correct date
        start_datetime = Time.new(
          date_obj.year, 
          date_obj.month, 
          date_obj.day, 
          hour, 
          minute, 
          0, # seconds
          restaurant.timezone_offset
        )
        
        Rails.logger.info "Successfully parsed date: #{date_obj} and time: #{hour}:#{minute}"
        Rails.logger.info "Start datetime for capacity check: #{start_datetime}"
      rescue => e
        Rails.logger.error "Error parsing date/time for capacity check: #{e.message}"
        return { 
          success: false, 
          errors: ["Invalid date or time format"],
          status: :unprocessable_entity 
        }
      end
      
      # Use restaurant's standard reservation duration
      reservation_duration = restaurant.reservation_duration || 60
      end_datetime = start_datetime + reservation_duration.minutes
      
      # Check if there are any restaurant-level blocks first (closed days, blocked periods)
      # We want to be more direct here rather than relying on check_availability
      # since that method is too strict in some cases
      Rails.logger.info "CAPACITY CHECK: Checking date=#{date_str}, time=#{time_str}, party_size=#{party_size}, location_id=#{location_id}"
      
      # Parse date and check operating hours
      date_obj = Date.parse(date_str) rescue Date.today
      day_of_week_num = date_obj.wday # 0 = Sunday, 1 = Monday, etc.
      operating_hour = scope_query(OperatingHour).find_by(day_of_week: day_of_week_num)
      
      # Restaurant is closed on this day
      if operating_hour.nil? || operating_hour.closed
        return { 
          success: true,
          available: false,
          max_party_size: 0,
          total_capacity: 0,
          booked_seats: 0,
          reason: "Restaurant is closed on this day"
        }
      end
      
      # Check if there are any blocked periods that affect this time
      blocked_period = scope_query(BlockedPeriod).active
        .where('start_time <= ? AND end_time >= ?', start_datetime, start_datetime)
        .where(location_id.present? ? 'location_id IS NULL OR location_id = ?' : 'location_id IS NULL', location_id)
        .first
      
      if blocked_period.present?
        return {
          success: true,
          available: false,
          max_party_size: 0,
          total_capacity: 0,
          booked_seats: 0,
          reason: "Time is blocked: #{blocked_period.reason}"
        }
      end
      
      # Check if the requested time is within operating hours
      hour, minute = time_str.split(':').map(&:to_i)
      request_time = Time.new(1, 1, 1, hour, minute, 0) # Using a dummy date for time-only comparison
      
      # Get opening and closing times for comparison
      opening_time = operating_hour.open_time
      closing_time = operating_hour.close_time
      
      # Convert operating hours to comparable times
      opening_time_obj = Time.new(1, 1, 1, opening_time.hour, opening_time.min, 0)
      closing_time_obj = Time.new(1, 1, 1, closing_time.hour, closing_time.min, 0)
      
      Rails.logger.info "CAPACITY: Time check - Request time: #{request_time.strftime('%H:%M')}, Opening: #{opening_time_obj.strftime('%H:%M')}, Closing: #{closing_time_obj.strftime('%H:%M')}"
      
      if request_time < opening_time_obj || request_time > closing_time_obj
        Rails.logger.info "CAPACITY: Restaurant is closed at this time (#{time_str})"
        return { 
          success: true,
          available: false,
          max_party_size: 0,
          total_capacity: 0,
          booked_seats: 0,
          reason: "Restaurant is closed at this time"
        }
      end
      
      # Check if party size exceeds restaurant maximum
      max_restaurant_party_size = restaurant.max_party_size
      if party_size.to_i > max_restaurant_party_size
        return {
          success: true,
          available: false,
          max_party_size: max_restaurant_party_size,
          total_capacity: 0,
          booked_seats: 0,
          reason: "Party size exceeds restaurant maximum of #{max_restaurant_party_size}"
        }
      end
      
      # If we get here, the time slot is available in principle, now check capacity
      
      # Get total restaurant capacity
      total_capacity = 0
      begin
        # Get seats from the restaurant, using location-specific seats if location_id is provided
        if location_id.present?
          seats = restaurant.location_seats(location_id) rescue []
          Rails.logger.info "CAPACITY: Using location-specific seats for location_id=#{location_id}"
        else
          seats = restaurant.current_seats rescue []
        end
        Rails.logger.info "CAPACITY: Found #{seats.count} seats for restaurant"
        
        # Sum up seat capacities
        if seats.present?
          seats.each do |seat|
            if seat.respond_to?(:capacity) && seat.capacity.present? && seat.capacity.to_i > 0
              total_capacity += seat.capacity.to_i
            else
              total_capacity += 1
            end
          end
        end
        
        # IMPORTANT: If no seats found or total capacity is zero, force a default value
        # This ensures we don't have empty seats causing zero capacity
        if total_capacity.zero?
          if restaurant.respond_to?(:admin_settings) && 
             restaurant.admin_settings.present? && 
             restaurant.admin_settings[:seating_capacity].present?
            total_capacity = restaurant.admin_settings[:seating_capacity].to_i
            Rails.logger.info "CAPACITY: Using restaurant admin setting: #{total_capacity} seats"
          else
            # Default to 18 seats as a fallback
            total_capacity = 18
            Rails.logger.info "CAPACITY: Using fallback default: #{total_capacity} seats"
          end
        else
          Rails.logger.info "CAPACITY: Calculated seat capacity: #{total_capacity} seats"
        end
      rescue => e
        Rails.logger.error "Error calculating capacity: #{e.message}"
        total_capacity = 18  # Default fallback
        Rails.logger.info "CAPACITY: Using error recovery fallback: #{total_capacity} seats"
      end
      
      # Absolute failsafe: Ensure total_capacity is never zero
      if total_capacity.zero?
        total_capacity = 18
        Rails.logger.info "CAPACITY: Using zero-capacity failsafe: #{total_capacity} seats"
      end
      
      # Get overlapping reservations for this time slot
      # This checks for any reservations that would overlap with the selected time period
      # For a reservation to overlap, it must start before the end of our slot and end after the start of our slot
      Rails.logger.info "CAPACITY: Checking for overlapping reservations between #{start_datetime} and #{end_datetime}"
      
      overlapping_reservations = scope_query(Reservation)
        .where.not(status: %w[canceled finished no_show])
        .where("(start_time < ? AND end_time > ?)", end_datetime, start_datetime)
      
      # Filter by location if provided
      if location_id.present?
        overlapping_reservations = overlapping_reservations.where(location_id: location_id)
        Rails.logger.info "CAPACITY CHECK: Filtering by location_id=#{location_id}"
      end
      
      # Calculate total seats already booked
      booked_seats = overlapping_reservations.sum(:party_size)
      
      # Calculate remaining capacity
      remaining_capacity = total_capacity - booked_seats
      remaining_capacity = 0 if remaining_capacity < 0
      
      # Check if there's a restaurant max party size limit
      max_party_size = restaurant.max_party_size
      if max_party_size > 0 && max_party_size < remaining_capacity
        remaining_capacity = max_party_size
      end
      
      # Log the calculation
      Rails.logger.info "CAPACITY: For #{date_str} at #{time_str}, total: #{total_capacity}, booked: #{booked_seats}, available: #{remaining_capacity}"
      # Determine if requested party size can be accommodated
      party_size_accommodated = remaining_capacity >= party_size
      
      # Return the maximum party size and availability
      {
        success: true,
        available: party_size_accommodated, # Only available if we can accommodate the requested party size
        max_party_size: remaining_capacity,
        total_capacity: total_capacity,
        booked_seats: booked_seats
      }
    rescue => e
      Rails.logger.error "CAPACITY ERROR: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      return { 
        success: false, 
        errors: ["Error calculating capacity: #{e.message}"],
        status: :internal_server_error 
      }
    end
  end

  def get_operating_hours
    # Validate tenant context first
    validate_tenant_context
    
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
    # Validate tenant context first
    validate_tenant_context
    
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
