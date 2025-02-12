# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  default from: 'Hafaloha <4lmshimizu@gmail.com>'

  def order_confirmation(order)
    @order = order
    mail to: @order.contact_email,
         subject: "Your Hafaloha Order Confirmation ##{@order.id}"
  end

  def order_ready(order)
    @order = order
    mail to: @order.contact_email,
         subject: "Håfaloha Order ##{@order.id} is Ready!"
  end
end
