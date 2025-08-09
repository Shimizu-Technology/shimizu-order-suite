# app/mailers/wholesale_order_mailer.rb
class WholesaleOrderMailer < ApplicationMailer
  include MailerHelper
  
  def order_confirmation(order)
    @order = order
    @restaurant = order.restaurant
    @fundraiser = order.fundraiser
    @participant = order.participant
    @order_items = order.order_items.includes(:item)
    @header_color = email_header_color_for(@restaurant)
    
    # Calculate order summary
    @subtotal = @order.total_cents / 100.0
    @total = @subtotal
    
    mail(
      to: @order.customer_email,
      from: restaurant_from_address(@restaurant),
      subject: "Wholesale Order Confirmation ##{@order.order_number} - #{@fundraiser.name}"
    )
  end
  
  def order_fulfilled(order)
    @order = order
    @restaurant = order.restaurant
    @fundraiser = order.fundraiser
    @participant = order.participant
    @order_items = order.order_items.includes(:item)
    @header_color = email_header_color_for(@restaurant)
    
    # Calculate order summary
    @subtotal = @order.total_cents / 100.0
    @total = @subtotal
    
    mail(
      to: @order.customer_email,
      from: restaurant_from_address(@restaurant),
      subject: "Your Wholesale Order ##{@order.order_number} Has Been Fulfilled!"
    )
  end
  
  def order_ready(order)
    @order = order
    @restaurant = order.restaurant
    @fundraiser = order.fundraiser
    @participant = order.participant
    @order_items = order.order_items.includes(:item)
    @header_color = email_header_color_for(@restaurant)
    
    # Calculate order summary
    @subtotal = @order.total_cents / 100.0
    @total = @subtotal
    
    mail(
      to: @order.customer_email,
      from: restaurant_from_address(@restaurant),
      subject: "Your Wholesale Order ##{@order.order_number} is Ready for Pickup!"
    )
  end
  
  def order_shipped(order)
    @order = order
    @restaurant = order.restaurant
    @fundraiser = order.fundraiser
    @participant = order.participant
    @order_items = order.order_items.includes(:item)
    @header_color = email_header_color_for(@restaurant)
    
    mail(
      to: @order.customer_email,
      from: restaurant_from_address(@restaurant),
      subject: "Your Wholesale Order ##{@order.order_number} Has Shipped!"
    )
  end
  
  def order_delivered(order)
    @order = order
    @restaurant = order.restaurant
    @fundraiser = order.fundraiser
    @participant = order.participant
    @order_items = order.order_items.includes(:item)
    @header_color = email_header_color_for(@restaurant)
    
    mail(
      to: @order.customer_email,
      from: restaurant_from_address(@restaurant),
      subject: "Your Wholesale Order ##{@order.order_number} Has Been Delivered!"
    )
  end
  
  private
  
  def get_restaurant_for(order)
    order.restaurant
  end

  def email_header_color_for(restaurant)
    restaurant&.admin_settings&.dig("email_header_color") || "#c1902f" # Hafaloha gold
  end

  def restaurant_from_address(restaurant)
    restaurant_name = restaurant&.name || 'Restaurant'
    formatted_name = restaurant_name.to_s.gsub('"', '\"')
    "#{formatted_name} <noreply@shimizu-order-suite.com>"
  end
end