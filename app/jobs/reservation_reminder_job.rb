class ReservationReminderJob < ApplicationJob
  queue_as :default

  def perform
    # Find all reservations happening between 24-25 hours from now that are still active
    # This ensures we only send reminders for upcoming reservations that haven't been cancelled
    start_time = 24.hours.from_now
    end_time = 25.hours.from_now
    
    upcoming_reservations = Reservation.where(
      status: 'booked',
      start_time: start_time..end_time
    )
    
    upcoming_reservations.find_each do |reservation|
      # Skip if no email is provided
      next unless reservation.contact_email.present?
      
      # Get the restaurant notification settings
      restaurant = reservation.restaurant
      notification_channels = restaurant.admin_settings&.dig("notification_channels", "reservations") || {}
      
      # Send reminder email unless explicitly disabled
      if notification_channels["reminder_email"] != false
        ReservationMailer.reservation_reminder(reservation).deliver_later
      end
      
      # Optionally send an SMS reminder if enabled
      if notification_channels["reminder_sms"] != false && reservation.contact_phone.present?
        restaurant_name = restaurant.name
        # Use custom SMS sender ID if set, otherwise use restaurant name
        sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name
        
        message_body = <<~MSG.squish
          Hi #{reservation.contact_name}, this is a reminder about your reservation tomorrow
          at #{reservation.start_time.strftime("%I:%M %p")} at #{restaurant_name}.
          Party size: #{reservation.party_size}. We look forward to serving you!
        MSG
        
        ClicksendClient.send_text_message(
          to:   reservation.contact_phone,
          body: message_body,
          from: sms_sender
        )
      end
    end
  end
end
