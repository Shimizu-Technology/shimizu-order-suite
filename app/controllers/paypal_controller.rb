# frozen_string_literal: true

class PaypalController < ApplicationController
  include RestaurantScope
  before_action :validate_amount, only: [:create_order]
  skip_before_action :verify_authenticity_token, only: [:webhook]

  # POST /paypal/create_order
  def create_order
    request = PayPalCheckoutSdk::Orders::OrdersCreateRequest.new
    request.request_body({
      intent: 'CAPTURE',
      purchase_units: [{
        amount: {
          currency_code: 'USD',
          value: params[:amount]
        },
        # Add reference_id for tracking which restaurant the order belongs to
        reference_id: "restaurant_#{current_restaurant.id}"
      }]
    })

    begin
      client = PaypalHelper.client
      response = client.execute(request)
      
      # The order ID can be retrieved from the response
      order_id = response.result.id
      
      # Store order details in a temporary storage if needed
      # You can associate this with a cart/session or pending order
      
      render json: { orderId: order_id }, status: :ok
    rescue PayPalHttp::HttpError => e
      Rails.logger.error "PayPal Order Create Failed: #{e.status_code} #{e.message}"
      render json: { error: "PayPal order creation failed: #{e.message}" }, status: :unprocessable_entity
    end
  end

  # POST /paypal/capture_order
  def capture_order
    order_id = params[:orderID]
    
    begin
      request = PayPalCheckoutSdk::Orders::OrdersCaptureRequest.new(order_id)
      client = PaypalHelper.client
      response = client.execute(request)
      
      capture_status = response.result.status # Should be "COMPLETED"
      
      # Extract transaction details for your records
      transaction_id = response.result.purchase_units[0].payments.captures[0].id
      payment_amount = response.result.purchase_units[0].payments.captures[0].amount.value
      
      # Update your order/payment records based on the transaction details
      # Note: In production, you'll want to validate the amount against your records
      
      render json: {
        status: capture_status,
        transaction_id: transaction_id,
        amount: payment_amount
      }, status: :ok
    rescue PayPalHttp::HttpError => e
      Rails.logger.error "PayPal Order Capture Failed: #{e.status_code} #{e.message}"
      render json: { error: "PayPal capture failed: #{e.message}" }, status: :unprocessable_entity
    end
  end

  # POST /paypal/webhook
  def webhook
    # Get the webhook notification body
    webhook_body = request.body.read
    
    # Get the webhook signature from headers
    webhook_id = request.headers['PAYPAL-TRANSMISSION-ID']
    timestamp = request.headers['PAYPAL-TRANSMISSION-TIME']
    signature = request.headers['PAYPAL-TRANSMISSION-SIG']
    cert_url = request.headers['PAYPAL-CERT-URL']
    auth_algo = request.headers['PAYPAL-AUTH-ALGO']
    
    # Get the webhook secret from restaurant settings
    restaurant = find_restaurant
    webhook_secret = restaurant&.admin_settings&.dig('payment_gateway', 'paypal_webhook_secret')
    
    begin
      # Verify the webhook signature
      # In a real implementation, you would use PayPal's SDK to verify the signature
      # For now, we'll assume the verification passed
      
      # Parse the webhook event
      event_data = JSON.parse(webhook_body)
      event_type = event_data['event_type']
      
      # Log the event for debugging
      Rails.logger.info "Received PayPal webhook: #{event_type}"
      
      # Handle different event types
      case event_type
      when 'PAYMENT.CAPTURE.COMPLETED'
        handle_payment_completed(event_data)
      when 'PAYMENT.CAPTURE.DENIED'
        handle_payment_denied(event_data)
      when 'PAYMENT.CAPTURE.PENDING'
        handle_payment_pending(event_data)
      when 'PAYMENT.CAPTURE.REFUNDED'
        handle_payment_refunded(event_data)
      when 'PAYMENT.CAPTURE.REVERSED'
        handle_payment_reversed(event_data)
      when 'CHECKOUT.ORDER.APPROVED'
        handle_checkout_approved(event_data)
      when 'CHECKOUT.ORDER.COMPLETED'
        handle_checkout_completed(event_data)
      when 'CHECKOUT.ORDER.DECLINED'
        handle_checkout_declined(event_data)
      when 'PAYMENT.REFUND.COMPLETED'
        handle_refund_completed(event_data)
      when 'PAYMENT.REFUND.FAILED'
        handle_refund_failed(event_data)
      when 'CUSTOMER.DISPUTE.CREATED'
        handle_dispute_created(event_data)
      when 'CUSTOMER.DISPUTE.RESOLVED'
        handle_dispute_resolved(event_data)
      when 'CUSTOMER.DISPUTE.UPDATED'
        handle_dispute_updated(event_data)
      else
        Rails.logger.info "Unhandled PayPal webhook event type: #{event_type}"
      end
      
      render json: { status: 'success' }, status: :ok
    rescue JSON::ParserError => e
      Rails.logger.error "Invalid PayPal webhook payload: #{e.message}"
      render json: { error: 'Invalid payload' }, status: :bad_request
    rescue => e
      Rails.logger.error "PayPal webhook error: #{e.message}"
      render json: { error: 'Webhook processing error' }, status: :internal_server_error
    end
  end

  private

  def validate_amount
    amount = params[:amount].to_f
    
    if amount <= 0
      render json: { error: 'Invalid payment amount' }, status: :unprocessable_entity
      return
    end
    
    # Optionally validate against a maximum amount for security
    if amount > 10000
      render json: { error: 'Payment amount exceeds maximum allowed' }, status: :unprocessable_entity
      return
    end
  end
  
  # Event handler methods
  
  def handle_payment_completed(event_data)
    # Extract payment details from the event data
    resource = event_data['resource']
    transaction_id = resource['id']
    
    # The order_id might be in different places depending on the event structure
    # You'll need to adjust this based on actual PayPal webhook data
    payment_id = resource['supplementary_data']&.dig('related_ids', 'order_id') || 
                 resource['links']&.find { |link| link['rel'] == 'up' }&.dig('href')&.split('/')&.last
    
    amount = resource.dig('amount', 'value')
    
    # Find the order by payment_id or transaction_id
    order = Order.find_by(payment_id: payment_id) || 
            Order.find_by(transaction_id: transaction_id)
    
    if order
      # Update order status
      order.update(
        payment_status: 'paid',
        payment_method: 'paypal',
        payment_id: payment_id,
        transaction_id: transaction_id,
        payment_amount: amount.to_f
      )
      
      # Create payment record if needed
      unless order.order_payments.exists?(payment_type: 'initial')
        order.order_payments.create(
          payment_type: 'initial',
          amount: amount.to_f,
          payment_method: 'paypal',
          status: 'paid',
          transaction_id: transaction_id,
          payment_id: payment_id,
          description: "Initial payment"
        )
      end
      
      Rails.logger.info "Updated order #{order.id} as paid via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment completed but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end
  
  def handle_payment_denied(event_data)
    resource = event_data['resource']
    transaction_id = resource['id']
    payment_id = resource['supplementary_data']&.dig('related_ids', 'order_id') || 
                 resource['links']&.find { |link| link['rel'] == 'up' }&.dig('href')&.split('/')&.last
    
    order = Order.find_by(payment_id: payment_id) || 
            Order.find_by(transaction_id: transaction_id)
    
    if order
      order.update(
        payment_status: 'failed',
        payment_method: 'paypal'
      )
      
      Rails.logger.info "Updated order #{order.id} as failed via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment denied but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end
  
  def handle_payment_pending(event_data)
    resource = event_data['resource']
    transaction_id = resource['id']
    payment_id = resource['supplementary_data']&.dig('related_ids', 'order_id') || 
                 resource['links']&.find { |link| link['rel'] == 'up' }&.dig('href')&.split('/')&.last
    
    order = Order.find_by(payment_id: payment_id) || 
            Order.find_by(transaction_id: transaction_id)
    
    if order
      order.update(
        payment_status: 'pending',
        payment_method: 'paypal'
      )
      
      Rails.logger.info "Updated order #{order.id} as pending via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment pending but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end
  
  def handle_payment_refunded(event_data)
    resource = event_data['resource']
    transaction_id = resource['id']
    payment_id = resource['supplementary_data']&.dig('related_ids', 'order_id') || 
                 resource['links']&.find { |link| link['rel'] == 'up' }&.dig('href')&.split('/')&.last
    
    refund_amount = resource.dig('amount', 'value').to_f
    
    order = Order.find_by(payment_id: payment_id) || 
            Order.find_by(transaction_id: transaction_id)
    
    if order
      # Check if it's a full or partial refund
      if refund_amount >= order.payment_amount.to_f
        # Full refund
        order.update(
          payment_status: 'refunded',
          status: Order::STATUS_REFUNDED,
          refund_amount: refund_amount
        )
      else
        # Partial refund
        order.update(
          payment_status: 'partially_refunded',
          status: Order::STATUS_PARTIALLY_REFUNDED,
          refund_amount: refund_amount
        )
      end
      
      # Create a refund payment record
      order.order_payments.create(
        payment_type: 'refund',
        amount: refund_amount,
        payment_method: 'paypal',
        status: 'completed',
        transaction_id: transaction_id,
        payment_id: payment_id,
        description: "Refund"
      )
      
      Rails.logger.info "Updated order #{order.id} as refunded via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment refunded but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end
  
  def handle_payment_reversed(event_data)
    resource = event_data['resource']
    transaction_id = resource['id']
    payment_id = resource['supplementary_data']&.dig('related_ids', 'order_id') || 
                 resource['links']&.find { |link| link['rel'] == 'up' }&.dig('href')&.split('/')&.last
    
    order = Order.find_by(payment_id: payment_id) || 
            Order.find_by(transaction_id: transaction_id)
    
    if order
      order.update(
        payment_status: 'reversed',
        status: Order::STATUS_REFUNDED
      )
      
      Rails.logger.info "Updated order #{order.id} as reversed via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment reversed but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end
  
  def handle_checkout_approved(event_data)
    # This event occurs when a buyer approves a payment
    # We don't need to do anything here as we'll wait for the PAYMENT.CAPTURE.COMPLETED event
    Rails.logger.info "PayPal checkout approved: #{event_data['id']}"
  end
  
  def handle_checkout_completed(event_data)
    # This event occurs when a checkout is completed
    # Similar to PAYMENT.CAPTURE.COMPLETED
    resource = event_data['resource']
    order_id = resource['id']
    
    # Find the order by payment_id
    order = Order.find_by(payment_id: order_id)
    
    if order
      # Update order status
      order.update(
        payment_status: 'paid',
        payment_method: 'paypal'
      )
      
      Rails.logger.info "Updated order #{order.id} as paid via PayPal checkout completed webhook"
    else
      Rails.logger.warn "PayPal checkout completed but no matching order found. Order ID: #{order_id}"
    end
  end
  
  def handle_checkout_declined(event_data)
    # This event occurs when a checkout is declined
    resource = event_data['resource']
    order_id = resource['id']
    
    # Find the order by payment_id
    order = Order.find_by(payment_id: order_id)
    
    if order
      # Update order status
      order.update(
        payment_status: 'failed',
        payment_method: 'paypal'
      )
      
      Rails.logger.info "Updated order #{order.id} as failed via PayPal checkout declined webhook"
    else
      Rails.logger.warn "PayPal checkout declined but no matching order found. Order ID: #{order_id}"
    end
  end
  
  def handle_refund_completed(event_data)
    # This is similar to PAYMENT.CAPTURE.REFUNDED
    # But we'll handle it separately in case the event structure is different
    resource = event_data['resource']
    refund_id = resource['id']
    payment_id = resource['parent_payment']
    
    refund_amount = resource.dig('amount', 'total').to_f
    
    order = Order.find_by(payment_id: payment_id)
    
    if order
      # Check if it's a full or partial refund
      if refund_amount >= order.payment_amount.to_f
        # Full refund
        order.update(
          payment_status: 'refunded',
          status: Order::STATUS_REFUNDED,
          refund_amount: refund_amount
        )
      else
        # Partial refund
        order.update(
          payment_status: 'partially_refunded',
          status: Order::STATUS_PARTIALLY_REFUNDED,
          refund_amount: refund_amount
        )
      end
      
      # Create a refund payment record
      order.order_payments.create(
        payment_type: 'refund',
        amount: refund_amount,
        payment_method: 'paypal',
        status: 'completed',
        transaction_id: refund_id,
        payment_id: payment_id,
        description: "Refund"
      )
      
      Rails.logger.info "Updated order #{order.id} as refunded via PayPal refund completed webhook"
    else
      Rails.logger.warn "PayPal refund completed but no matching order found. Payment ID: #{payment_id}"
    end
  end
  
  def handle_refund_failed(event_data)
    resource = event_data['resource']
    refund_id = resource['id']
    payment_id = resource['parent_payment']
    
    order = Order.find_by(payment_id: payment_id)
    
    if order
      # Log the failed refund
      Rails.logger.error "Refund failed for order #{order.id}. Refund ID: #{refund_id}"
    else
      Rails.logger.warn "PayPal refund failed but no matching order found. Payment ID: #{payment_id}"
    end
  end
  
  def handle_dispute_created(event_data)
    resource = event_data['resource']
    dispute_id = resource['dispute_id']
    transaction_id = resource['disputed_transactions']&.first&.dig('buyer_transaction_id')
    
    order = Order.find_by(transaction_id: transaction_id)
    
    if order
      order.update(
        payment_status: 'disputed',
        dispute_reason: resource['reason']
      )
      
      Rails.logger.info "Updated order #{order.id} as disputed via PayPal dispute created webhook"
    else
      Rails.logger.warn "PayPal dispute created but no matching order found. Transaction ID: #{transaction_id}"
    end
  end
  
  def handle_dispute_resolved(event_data)
    resource = event_data['resource']
    dispute_id = resource['dispute_id']
    transaction_id = resource['disputed_transactions']&.first&.dig('buyer_transaction_id')
    
    order = Order.find_by(transaction_id: transaction_id)
    
    if order
      # Check the dispute outcome
      if resource['status'] == 'RESOLVED'
        if resource['dispute_outcome'] == 'BUYER_FAVOR'
          # Buyer won the dispute
          order.update(
            payment_status: 'refunded',
            status: Order::STATUS_REFUNDED
          )
        else
          # Seller won the dispute
          order.update(
            payment_status: 'paid'
          )
        end
      end
      
      Rails.logger.info "Updated order #{order.id} based on resolved dispute via PayPal webhook"
    else
      Rails.logger.warn "PayPal dispute resolved but no matching order found. Transaction ID: #{transaction_id}"
    end
  end
  
  def handle_dispute_updated(event_data)
    # Just log the update for now
    resource = event_data['resource']
    dispute_id = resource['dispute_id']
    transaction_id = resource['disputed_transactions']&.first&.dig('buyer_transaction_id')
    
    Rails.logger.info "PayPal dispute updated: #{dispute_id} for transaction #{transaction_id}"
  end
  
  def find_restaurant
    # Try to get restaurant from restaurant_id parameter
    restaurant = Restaurant.find_by(id: params[:restaurant_id])
    
    # If no restaurant_id parameter was provided, try to get the first restaurant
    # This is a fallback for requests that don't specify a restaurant
    restaurant ||= Restaurant.first if Restaurant.exists?
    
    return restaurant
  end
end
