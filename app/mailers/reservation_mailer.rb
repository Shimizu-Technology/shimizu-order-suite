# app/mailers/reservation_mailer.rb
class ReservationMailer < ApplicationMailer
  # e.g. a single method for the booking confirmation
  def booking_confirmation(reservation)
    @reservation = reservation
    @restaurant = get_restaurant_for(@reservation)
    @header_color = email_header_color_for(@restaurant)

    mail(
      to: @reservation.contact_email,
      from: restaurant_from_address(@restaurant),
      subject: "Your #{@restaurant&.name || 'Restaurant'} Reservation Confirmation"
    )
  end
end
