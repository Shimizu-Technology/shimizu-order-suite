# app/mailers/reservation_mailer.rb
class ReservationMailer < ApplicationMailer
  # e.g. a single method for the booking confirmation
  def booking_confirmation(reservation)
    @reservation = reservation
    # For the email template, you can reference @reservation.contact_name, etc.
    # If you track a user ID, you can do e.g. @reservation.user… etc.

    mail(
      to:    @reservation.contact_email,
      subject: "Your Rotary Sushi Reservation Confirmation"
    )
  end
end
