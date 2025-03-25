# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  def order_confirmation(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "Your #{@restaurant&.name || 'Restaurant'} Order Confirmation ##{@order.id}"
  end

  def order_ready(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "#{@restaurant&.name || 'Restaurant'} Order ##{@order.id} is Ready!"
  end

  def order_preparing(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "Your #{@restaurant&.name || 'Restaurant'} Order ##{@order.id} is Being Prepared"
  end

  def order_eta_updated(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "Your #{@restaurant&.name || 'Restaurant'} Order ##{@order.id} Pickup Time Has Been Updated"
  end
  
  def payment_link(email, payment_url, order, restaurant_name = nil, restaurant_logo = nil, template = nil)
    @order = order
    @payment_url = payment_url
    @restaurant = get_restaurant_for(@order)
    @restaurant_name = restaurant_name || @restaurant&.name || 'Restaurant'
    @restaurant_logo = restaurant_logo || @restaurant&.logo_url
    @header_color = email_header_color_for(@restaurant)
    @template = template || 'default_payment_link'
    
    mail to: email,
         from: restaurant_from_address(@restaurant),
         subject: "Payment Link for #{@restaurant_name} Order ##{@order.id}"
  end
  
  def payment_confirmation(email, order, restaurant_name = nil, restaurant_logo = nil)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @restaurant_name = restaurant_name || @restaurant&.name || 'Restaurant'
    @restaurant_logo = restaurant_logo || @restaurant&.logo_url
    @header_color = email_header_color_for(@restaurant)
    
    mail to: email,
         from: restaurant_from_address(@restaurant),
         subject: "Payment Received for #{@restaurant_name} Order ##{@order.id}"
  end
end
