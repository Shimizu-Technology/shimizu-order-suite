# frozen_string_literal: true

class PaypalController < ApplicationController
  include TenantIsolation
  
  before_action :ensure_tenant_context, except: [:webhook]
  before_action :validate_amount, only: [:create_order]

  # POST /paypal/create_order
  def create_order
    result = tenant_paypal_service.create_order(
      params[:amount],
      params[:currency] || "USD"
    )

    if result[:success]
      render json: { orderId: result[:order_id] }, status: :ok
    else
      render json: { error: result[:errors].join(', ') }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /paypal/capture_order
  def capture_order
    result = tenant_paypal_service.capture_order(params[:orderID])

    if result[:success]
      render json: {
        status: result[:status],
        transaction_id: result[:capture_id],
        amount: result[:amount],
        currency: params[:currency] || "USD"
      }, status: :ok
    else
      render json: { error: result[:errors].join(', ') }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /paypal/webhook
  def webhook
    # Get the webhook notification body
    payload = request.body.read
    
    # Get the restaurant ID from the URL parameter
    restaurant_id = params[:restaurant_id]
    
    # Find the restaurant for this webhook
    restaurant = Restaurant.find_by(id: restaurant_id)
    
    unless restaurant
      Rails.logger.error "PayPal webhook failed: Restaurant not found"
      render json: { error: "Restaurant not found" }, status: :not_found
      return
    end
    
    # Set the current restaurant context for the tenant service
    @current_restaurant = restaurant

    begin
      # Process the webhook using the tenant service
      result = tenant_paypal_service.process_webhook(payload, request.headers)
      
      if result[:success]
        # Parse the event data and type
        event_data = JSON.parse(payload)
        event_type = event_data['event_type']
        
        # Handle different event types
        case event_type
        when "CUSTOMER.DISPUTE.CREATED"
          handle_dispute_created(event_data)
        when "CUSTOMER.DISPUTE.RESOLVED"
          handle_dispute_resolved(event_data)
        when "CUSTOMER.DISPUTE.UPDATED"
          handle_dispute_updated(event_data)
        else
          Rails.logger.info "Unhandled PayPal webhook event type: #{event_type}"
        end

        render json: { status: "success" }, status: :ok
      else
        Rails.logger.error "PayPal webhook processing failed: #{result[:errors]}"
        render json: { error: result[:errors].join(', ') }, status: result[:status] || :bad_request
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Invalid PayPal webhook payload: #{e.message}"
      render json: { error: "Invalid payload" }, status: :bad_request
    rescue => e
      Rails.logger.error "PayPal webhook error: #{e.message}"
      render json: { error: "Webhook processing error" }, status: :internal_server_error
    end
  end

  private

  def validate_amount
    amount = params[:amount].to_f

    if amount <= 0
      render json: { error: "Invalid payment amount" }, status: :unprocessable_entity
      return
    end

    # Optionally validate against a maximum amount for security
    if amount > 10000
      render json: { error: "Payment amount exceeds maximum allowed" }, status: :unprocessable_entity
      nil
    end
  end

  # Event handler methods

  def handle_payment_completed(event_data)
    # Extract payment details from the event data
    resource = event_data["resource"]
    transaction_id = resource["id"]

    # The order_id might be in different places depending on the event structure
    # You'll need to adjust this based on actual PayPal webhook data
    payment_id = (resource["supplementary_data"]&.dig("related_ids", "order_id") ||
                 resource["links"]&.find { |link| link["rel"] == "up" }&.dig("href")&.split("/")&.last)

    amount = resource.dig("amount", "value")

    # Find the order by payment_id or transaction_id
    order = (Order.find_by(payment_id: payment_id) ||
            Order.find_by(transaction_id: transaction_id))

    if order
      # Update order status
      order.update(
        payment_status: "paid",
        payment_method: "paypal",
        payment_id: payment_id,
        transaction_id: transaction_id,
        payment_amount: amount.to_f
      )

      # Create payment record if needed
      unless order.order_payments.exists?(payment_type: "initial")
        order.order_payments.create(
          payment_type: "initial",
          amount: amount.to_f,
          payment_method: "paypal",
          status: "paid",
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
    resource = event_data["resource"]
    transaction_id = resource["id"]
    payment_id = (resource["supplementary_data"]&.dig("related_ids", "order_id") ||
                 resource["links"]&.find { |link| link["rel"] == "up" }&.dig("href")&.split("/")&.last)

    order = (Order.find_by(payment_id: payment_id) ||
            Order.find_by(transaction_id: transaction_id))

    if order
      order.update(
        payment_status: "failed",
        payment_method: "paypal"
      )

      Rails.logger.info "Updated order #{order.id} as failed via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment denied but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end

  def handle_payment_pending(event_data)
    resource = event_data["resource"]
    transaction_id = resource["id"]
    payment_id = (resource["supplementary_data"]&.dig("related_ids", "order_id") ||
                 resource["links"]&.find { |link| link["rel"] == "up" }&.dig("href")&.split("/")&.last)

    order = (Order.find_by(payment_id: payment_id) ||
            Order.find_by(transaction_id: transaction_id))

    if order
      order.update(
        payment_status: "pending",
        payment_method: "paypal"
      )

      Rails.logger.info "Updated order #{order.id} as pending via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment pending but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end

  def handle_payment_refunded(event_data)
    resource = event_data["resource"]
    transaction_id = resource["id"]
    payment_id = (resource["supplementary_data"]&.dig("related_ids", "order_id") ||
                 resource["links"]&.find { |link| link["rel"] == "up" }&.dig("href")&.split("/")&.last)

    refund_amount = resource.dig("amount", "value").to_f

    order = (Order.find_by(payment_id: payment_id) ||
            Order.find_by(transaction_id: transaction_id))

    if order
      # Check if it's a full or partial refund
      if refund_amount >= order.payment_amount.to_f
        # Full refund
        order.update(
          payment_status: "refunded",
          status: Order::STATUS_REFUNDED,
          refund_amount: refund_amount
        )
      else
        # Partial refund
        order.update(
          payment_status: "refunded",
          # No longer changing status for partial refunds
          refund_amount: refund_amount
        )
      end

      # Create a refund payment record
      refund_payment = order.order_payments.create(
        payment_type: "refund",
        amount: refund_amount,
        payment_method: "paypal",
        status: "completed",
        transaction_id: transaction_id,
        payment_id: payment_id,
        description: "PayPal webhook refund"
      )

      # Send refund notification email to customer
      begin
        if order.contact_email.present?
          Rails.logger.info("Sending PayPal webhook refund notification email to #{order.contact_email} for order #{order.id}")
          OrderMailer.refund_notification(order, refund_payment, []).deliver_later
          Rails.logger.info("PayPal webhook refund notification email queued successfully")
        end
      rescue => email_error
        Rails.logger.error("Failed to send PayPal webhook refund notification email for order #{order.id}: #{email_error.message}")
      end
      
      # Send refund notification SMS to customer
      begin
        if order.contact_phone.present?
          restaurant = order.restaurant
          notification_channels = restaurant.admin_settings&.dig("notification_channels", "orders") || {}
          
          # Send SMS if enabled (default to true for backward compatibility)
          if notification_channels["sms"] != false
            sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant.name
            
            # Determine refund type and create appropriate message
            is_full_refund = refund_amount >= order.payment_amount.to_f
            refund_type = is_full_refund ? "full refund" : "partial refund"
            
            message_body = <<~MSG.squish
              Hi #{order.contact_name.presence || 'Customer'}, 
              we've processed a #{refund_type} of $#{sprintf("%.2f", refund_amount)} 
              for your #{restaurant.name} order ##{order.order_number.presence || order.id}. 
              You should receive your refund within 1-3 business days. 
              #{is_full_refund ? 'Thank you for your understanding.' : 'This is a partial refund - some items from your order are not affected.'}
            MSG
            
            Rails.logger.info("Sending PayPal webhook refund notification SMS to #{order.contact_phone} for order #{order.id}")
            SendSmsJob.perform_later(
              to: order.contact_phone,
              body: message_body,
              from: sms_sender
            )
            Rails.logger.info("PayPal webhook refund notification SMS queued successfully")
          end
        end
      rescue => sms_error
        Rails.logger.error("Failed to send PayPal webhook refund notification SMS for order #{order.id}: #{sms_error.message}")
      end

      Rails.logger.info "Updated order #{order.id} as refunded via PayPal webhook"
    else
      Rails.logger.warn "PayPal payment refunded but no matching order found. Transaction ID: #{transaction_id}, Payment ID: #{payment_id}"
    end
  end

  def handle_payment_reversed(event_data)
    resource = event_data["resource"]
    transaction_id = resource["id"]
    payment_id = (resource["supplementary_data"]&.dig("related_ids", "order_id") ||
                 resource["links"]&.find { |link| link["rel"] == "up" }&.dig("href")&.split("/")&.last)

    order = (Order.find_by(payment_id: payment_id) ||
            Order.find_by(transaction_id: transaction_id))

    if order
      order.update(
        payment_status: "reversed",
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
    resource = event_data["resource"]
    order_id = resource["id"]

    # Find the order by payment_id
    order = Order.find_by(payment_id: order_id)

    if order
      # Update order status
      order.update(
        payment_status: "paid",
        payment_method: "paypal"
      )

      Rails.logger.info "Updated order #{order.id} as paid via PayPal checkout completed webhook"
    else
      Rails.logger.warn "PayPal checkout completed but no matching order found. Order ID: #{order_id}"
    end
  end

  def handle_checkout_declined(event_data)
    # This event occurs when a checkout is declined
    resource = event_data["resource"]
    order_id = resource["id"]

    # Find the order by payment_id
    order = Order.find_by(payment_id: order_id)

    if order
      # Update order status
      order.update(
        payment_status: "failed",
        payment_method: "paypal"
      )

      Rails.logger.info "Updated order #{order.id} as failed via PayPal checkout declined webhook"
    else
      Rails.logger.warn "PayPal checkout declined but no matching order found. Order ID: #{order_id}"
    end
  end

  def handle_refund_completed(event_data)
    # This is similar to PAYMENT.CAPTURE.REFUNDED
    # But we'll handle it separately in case the event structure is different
    resource = event_data["resource"]
    refund_id = resource["id"]
    payment_id = resource["parent_payment"]

    refund_amount = resource.dig("amount", "total").to_f

    order = Order.find_by(payment_id: payment_id)

    if order
      # Check if it's a full or partial refund
      if refund_amount >= order.payment_amount.to_f
        # Full refund
        order.update(
          payment_status: "refunded",
          status: Order::STATUS_REFUNDED,
          refund_amount: refund_amount
        )
      else
        # Partial refund
        order.update(
          payment_status: "refunded",
          # No longer changing status for partial refunds
          refund_amount: refund_amount
        )
      end

      # Create a refund payment record
      refund_payment = order.order_payments.create(
        payment_type: "refund",
        amount: refund_amount,
        payment_method: "paypal",
        status: "completed",
        transaction_id: refund_id,
        payment_id: payment_id,
        description: "PayPal refund completed webhook"
      )

      # Send refund notification email to customer
      begin
        if order.contact_email.present?
          Rails.logger.info("Sending PayPal refund completed notification email to #{order.contact_email} for order #{order.id}")
          OrderMailer.refund_notification(order, refund_payment, []).deliver_later
          Rails.logger.info("PayPal refund completed notification email queued successfully")
        end
      rescue => email_error
        Rails.logger.error("Failed to send PayPal refund completed notification email for order #{order.id}: #{email_error.message}")
      end
      
      # Send refund notification SMS to customer
      begin
        if order.contact_phone.present?
          restaurant = order.restaurant
          notification_channels = restaurant.admin_settings&.dig("notification_channels", "orders") || {}
          
          # Send SMS if enabled (default to true for backward compatibility)
          if notification_channels["sms"] != false
            sms_sender = restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant.name
            
            # Determine refund type and create appropriate message
            is_full_refund = refund_amount >= order.payment_amount.to_f
            refund_type = is_full_refund ? "full refund" : "partial refund"
            
            message_body = <<~MSG.squish
              Hi #{order.contact_name.presence || 'Customer'}, 
              we've processed a #{refund_type} of $#{sprintf("%.2f", refund_amount)} 
              for your #{restaurant.name} order ##{order.order_number.presence || order.id}. 
              You should receive your refund within 1-3 business days. 
              #{is_full_refund ? 'Thank you for your understanding.' : 'This is a partial refund - some items from your order are not affected.'}
            MSG
            
            Rails.logger.info("Sending PayPal refund completed notification SMS to #{order.contact_phone} for order #{order.id}")
            SendSmsJob.perform_later(
              to: order.contact_phone,
              body: message_body,
              from: sms_sender
            )
            Rails.logger.info("PayPal refund completed notification SMS queued successfully")
          end
        end
      rescue => sms_error
        Rails.logger.error("Failed to send PayPal refund completed notification SMS for order #{order.id}: #{sms_error.message}")
      end

      Rails.logger.info "Updated order #{order.id} as refunded via PayPal refund completed webhook"
    else
      Rails.logger.warn "PayPal refund completed but no matching order found. Payment ID: #{payment_id}"
    end
  end

  def handle_refund_failed(event_data)
    resource = event_data["resource"]
    refund_id = resource["id"]
    payment_id = resource["parent_payment"]

    order = Order.find_by(payment_id: payment_id)

    if order
      # Log the failed refund
      Rails.logger.error "Refund failed for order #{order.id}. Refund ID: #{refund_id}"
    else
      Rails.logger.warn "PayPal refund failed but no matching order found. Payment ID: #{payment_id}"
    end
  end

  def handle_dispute_created(event_data)
    resource = event_data["resource"]
    dispute_id = resource["dispute_id"]
    transaction_id = resource["disputed_transactions"]&.first&.dig("buyer_transaction_id")

    order = Order.find_by(transaction_id: transaction_id)

    if order
      order.update(
        payment_status: "disputed",
        dispute_reason: resource["reason"]
      )

      Rails.logger.info "Updated order #{order.id} as disputed via PayPal dispute created webhook"
    else
      Rails.logger.warn "PayPal dispute created but no matching order found. Transaction ID: #{transaction_id}"
    end
  end

  def handle_dispute_resolved(event_data)
    resource = event_data["resource"]
    dispute_id = resource["dispute_id"]
    transaction_id = resource["disputed_transactions"]&.first&.dig("buyer_transaction_id")

    order = Order.find_by(transaction_id: transaction_id)

    if order
      # Check the dispute outcome
      if resource["status"] == "RESOLVED"
        if resource["dispute_outcome"] == "BUYER_FAVOR"
          # Buyer won the dispute
          order.update(
            payment_status: "refunded",
            status: Order::STATUS_REFUNDED
          )
        else
          # Seller won the dispute
          order.update(
            payment_status: "paid"
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
    resource = event_data["resource"]
    dispute_id = resource["dispute_id"]
    transaction_id = resource["disputed_transactions"]&.first&.dig("buyer_transaction_id")

    Rails.logger.info "PayPal dispute updated: #{dispute_id} for transaction #{transaction_id}"
  end

  def find_restaurant
    # Try to get restaurant from restaurant_id parameter
    restaurant = Restaurant.find_by(id: params[:restaurant_id])

    # If no restaurant_id parameter was provided, try to get the first restaurant
    # This is a fallback for requests that don't specify a restaurant
    restaurant ||= Restaurant.first if Restaurant.exists?

    restaurant
  end

  # Verify PayPal webhook signature
  # Based on PayPal's documentation: https://developer.paypal.com/api/rest/webhooks/
  def verify_paypal_webhook_signature(webhook_body, webhook_id, timestamp, signature, cert_url, auth_algo, paypal_webhook_id)
    # Check if all required headers are present
    return false if webhook_id.blank? || timestamp.blank? || signature.blank? || cert_url.blank? || auth_algo.blank?

    # Check if the webhook ID is configured
    return false if paypal_webhook_id.blank?

    # Check if the timestamp is recent (within 5 minutes)
    begin
      webhook_time = Time.parse(timestamp)
      time_diff = Time.now.utc - webhook_time
      return false if time_diff > 300 # 5 minutes in seconds
    rescue
      return false
    end

    # Get the restaurant to check test mode
    restaurant = find_restaurant

    # In test mode, skip full verification
    if restaurant&.admin_settings&.dig("payment_gateway", "test_mode")
      Rails.logger.info "PayPal webhook verification skipped in test mode"
      return true
    end

    # For production, we need to implement proper signature verification
    # This involves:
    # 1. Validating the certificate chain
    # 2. Extracting the public key from the certificate
    # 3. Creating a signature message from the webhook data
    # 4. Verifying the signature using the public key

    # Check if the webhook ID matches the one in our settings
    if webhook_id != paypal_webhook_id
      Rails.logger.error "PayPal webhook ID mismatch: received #{webhook_id}, expected #{paypal_webhook_id}"
      return false
    end

    # In a production environment, we would verify the signature here
    # For now, we'll log that we're doing basic verification
    Rails.logger.info "PayPal webhook basic verification passed. Webhook ID matches configuration."

    # Return true to indicate the webhook is valid
    true
  end
  
  def tenant_paypal_service
    @tenant_paypal_service ||= begin
      service = TenantPaypalService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
