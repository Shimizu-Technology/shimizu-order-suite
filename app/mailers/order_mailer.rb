# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  # Explicitly include the MailerHelper to ensure methods are available
  include MailerHelper
  
  # Define helper methods directly in the class as a fallback
  def get_restaurant_for(order)
    order.restaurant
  end

  def email_header_color_for(restaurant)
    # Get email header color from admin_settings, with a fallback to gold
    restaurant&.admin_settings&.dig("email_header_color") || "#D4AF37" # Default gold color
  end

  def restaurant_from_address(restaurant)
    # Format the email with restaurant name as display name and noreply@shimizu-order-suite.com as email
    restaurant_name = restaurant&.name || 'Restaurant'
    
    # Ensure the name is properly formatted for email headers (escape quotes)
    formatted_name = restaurant_name.to_s.gsub('"', '\"')
    
    # Return the properly formatted email address
    "#{formatted_name} <noreply@shimizu-order-suite.com>"
  end

  def order_confirmation(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "Your #{@restaurant&.name || 'Restaurant'} Order Confirmation ##{@order.order_number.presence || @order.id}"
  end

  def order_ready(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "#{@restaurant&.name || 'Restaurant'} Order ##{@order.order_number.presence || @order.id} is Ready!"
  end

  def order_preparing(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "Your #{@restaurant&.name || 'Restaurant'} Order ##{@order.order_number.presence || @order.id} is Being Prepared"
  end

  def order_eta_updated(order)
    @order = order
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)

    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: "Your #{@restaurant&.name || 'Restaurant'} Order ##{@order.order_number.presence || @order.id} Pickup Time Has Been Updated"
  end

  def refund_notification(order, refund_payment, refunded_items = [])
    @order = order
    @refund_payment = refund_payment
    @refunded_items = refunded_items
    @restaurant = get_restaurant_for(@order)
    @header_color = email_header_color_for(@restaurant)
    
    # Determine if this is a full or partial refund
    @is_partial_refund = refunded_items.present? && refunded_items.any?
    @refund_amount = refund_payment.amount
    @original_total = order.total
    
    # Calculate non-refunded items for partial refunds
    if @is_partial_refund
      @non_refunded_items = calculate_non_refunded_items(order.items, refunded_items)
    end
    
    # Subject line changes based on refund type
    refund_type = @is_partial_refund ? "Partial Refund" : "Full Refund"
    subject = "#{refund_type} Processed for #{@restaurant&.name || 'Restaurant'} Order ##{@order.order_number.presence || @order.id}"
    
    mail to: @order.contact_email,
         from: restaurant_from_address(@restaurant),
         subject: subject
  end

  private
  
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
         subject: "Payment Link for #{@restaurant_name} Order ##{@order.order_number.presence || @order.id}"
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
  
  # Helper method to calculate which items were NOT refunded for partial refunds
  def calculate_non_refunded_items(order_items, refunded_items)
    return [] unless order_items.present? && refunded_items.present?
    
    non_refunded = []
    
    # Create a hash of refunded quantities by item ID
    refunded_quantities = {}
    refunded_items.each do |item|
      item_id = item['id'].to_s
      refunded_quantities[item_id] = (refunded_quantities[item_id] || 0) + item['quantity'].to_i
    end
    
    # Calculate remaining quantities for each order item
    order_items.each do |item|
      item_id = item['id'].to_s
      original_quantity = item['quantity'].to_i
      refunded_quantity = refunded_quantities[item_id] || 0
      remaining_quantity = original_quantity - refunded_quantity
      
      if remaining_quantity > 0
        non_refunded << {
          'id' => item['id'],
          'name' => item['name'],
          'quantity' => remaining_quantity,
          'price' => item['price']
        }
      end
    end
    
    non_refunded
  end
end
