# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  default from: 'Hafaloha <4lmshimizu@gmail.com>'  # or whatever default "from" address you prefer

  def order_confirmation(order)
    @order = order
    mail(
      to: @order.contact_email,
      subject: "Your Hafaloha Order Confirmation ##{@order.id}"
    )
  end
end
