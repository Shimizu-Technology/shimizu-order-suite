# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  def order_confirmation(order)
    @order = order
    restaurant = get_restaurant_for(@order)
    
    mail to: @order.contact_email,
         from: from_address_for(restaurant),
         subject: "Your #{restaurant&.name || 'Restaurant'} Order Confirmation ##{@order.id}"
  end

  def order_ready(order)
    @order = order
    restaurant = get_restaurant_for(@order)
    
    mail to: @order.contact_email,
         from: from_address_for(restaurant),
         subject: "#{restaurant&.name || 'Restaurant'} Order ##{@order.id} is Ready!"
  end

  def order_preparing(order)
    @order = order
    restaurant = get_restaurant_for(@order)
    
    mail to: @order.contact_email,
         from: from_address_for(restaurant),
         subject: "Your #{restaurant&.name || 'Restaurant'} Order ##{@order.id} is Being Prepared"
  end
end
