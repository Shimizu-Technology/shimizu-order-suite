# app/mailers/reservation_mailer.rb
class ReservationMailer < ApplicationMailer
  # ApplicationMailer already includes MailerHelper and sets the default 'from' address

  # Sent when a reservation is initially created with 'booked' status
  def booking_created(reservation)
    @reservation = reservation
    @restaurant = get_restaurant_for(@reservation)
    @is_confirmed = false
    
    # Format the date/time for the email subject
    date_formatted = @reservation.start_time.strftime("%a, %b %d at %I:%M %p")
    
    # Add location name to subject only if it differs from restaurant name
    location_str = ""
    if @reservation.respond_to?(:location) && @reservation.location.present?
      # Only add location name if it's different from the restaurant name
      if @reservation.location.name != @restaurant&.name
        location_str = " (#{@reservation.location.name})"
      end
    end

    mail(
      to: @reservation.contact_email,
      from: from_address_for(@restaurant),
      subject: "Reservation Request: #{@restaurant&.name || 'Restaurant'}#{location_str} - #{date_formatted}"
    )
  end

  # Sent when a reservation is confirmed by staff
  def booking_confirmation(reservation)
    @reservation = reservation
    @restaurant = get_restaurant_for(@reservation)
    @is_confirmed = true
    
    # Format the date/time for the email subject
    date_formatted = @reservation.start_time.strftime("%a, %b %d at %I:%M %p")
    
    # Add location name to subject only if it differs from restaurant name
    location_str = ""
    if @reservation.respond_to?(:location) && @reservation.location.present?
      # Only add location name if it's different from the restaurant name
      if @reservation.location.name != @restaurant&.name
        location_str = " (#{@reservation.location.name})"
      end
    end

    mail(
      to: @reservation.contact_email,
      from: from_address_for(@restaurant),
      subject: "Reservation Confirmed: #{@restaurant&.name || 'Restaurant'}#{location_str} - #{date_formatted}"
    )
  end
  
  # Send a reminder 24 hours before the reservation
  def reservation_reminder(reservation)
    @reservation = reservation
    @restaurant = get_restaurant_for(@reservation)
    
    # Format the date/time
    date_formatted = @reservation.start_time.strftime("%a, %b %d at %I:%M %p")
    
    mail(
      to: @reservation.contact_email,
      from: from_address_for(@restaurant),
      subject: "Reminder: Your Reservation Tomorrow at #{@restaurant&.name || 'Restaurant'}"
    )
  end
  
  private
  
  # Helper method to determine the appropriate 'from' email address
  def from_address_for(restaurant)
    # Use a verified sender identity to comply with SendGrid requirements
    if restaurant&.name.present?
      "#{restaurant.name} <noreply@shimizu-order-suite.com>"
    else
      "ShimizuTechnology <noreply@shimizu-order-suite.com>"
    end
  end
  
  # Get the restaurant for a reservation
  # This is added here to ensure it's available in the mailer context
  # and to fix the NoMethodError for get_restaurant_for
  def get_restaurant_for(reservation)
    return nil unless reservation
    
    if reservation.respond_to?(:restaurant)
      reservation.restaurant
    elsif reservation.respond_to?(:restaurant_id)
      Restaurant.find_by(id: reservation.restaurant_id)
    else
      nil
    end
  end
end
