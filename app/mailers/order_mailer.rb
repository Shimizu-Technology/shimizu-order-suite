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
end
