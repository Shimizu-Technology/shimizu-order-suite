# app/mailers/reservation_mailer.rb
class ReservationMailer < ApplicationMailer
  # e.g. a single method for the booking confirmation
  def booking_confirmation(reservation)
    @reservation = reservation
    restaurant = get_restaurant_for(@reservation)
    
    mail(
      to: @reservation.contact_email,
      from: from_address_for(restaurant),
      subject: "Your #{restaurant&.name || 'Restaurant'} Reservation Confirmation"
    )
  end
end
