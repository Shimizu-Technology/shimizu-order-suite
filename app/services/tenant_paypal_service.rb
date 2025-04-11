# app/services/tenant_paypal_service.rb
class TenantPaypalService < TenantScopedService
  attr_accessor :current_user

  # Create a PayPal order
  def create_order(amount, currency = "USD")
    request = PayPalCheckoutSdk::Orders::OrdersCreateRequest.new
    
    request.request_body({
      intent: "CAPTURE",
      purchase_units: [{
        amount: {
          currency_code: currency,
          value: amount
        },
        # Add reference_id for tracking which restaurant the order belongs to
        reference_id: "restaurant_#{current_restaurant.id}"
      }]
    })

    begin
      client = PaypalHelper.client(current_restaurant)
      response = client.execute(request)

      # The order ID can be retrieved from the response
      order_id = response.result.id

      { success: true, order_id: order_id }
    rescue PayPalHttp::HttpError => e
      Rails.logger.error "PayPal Order Create Failed: #{e.status_code} #{e.message}"
      { success: false, errors: ["PayPal order creation failed: #{e.message}"], status: :unprocessable_entity }
    rescue => e
      Rails.logger.error "PayPal Order Create Failed: #{e.message}"
      { success: false, errors: ["An unexpected error occurred: #{e.message}"], status: :internal_server_error }
    end
  end

  # Capture a PayPal order
  def capture_order(order_id)
    begin
      request = PayPalCheckoutSdk::Orders::OrdersCaptureRequest.new(order_id)
      client = PaypalHelper.client(current_restaurant)
      response = client.execute(request)

      capture_status = response.result.status # Should be "COMPLETED"
      
      # Get the capture ID from the response
      capture_id = response.result.purchase_units[0].payments.captures[0].id
      
      # Get the transaction amount
      amount = response.result.purchase_units[0].payments.captures[0].amount.value
      
      { 
        success: true, 
        capture_id: capture_id,
        status: capture_status,
        amount: amount
      }
    rescue PayPalHttp::HttpError => e
      Rails.logger.error "PayPal Order Capture Failed: #{e.status_code} #{e.message}"
      { success: false, errors: ["PayPal order capture failed: #{e.message}"], status: :unprocessable_entity }
    rescue => e
      Rails.logger.error "PayPal Order Capture Failed: #{e.message}"
      { success: false, errors: ["An unexpected error occurred: #{e.message}"], status: :internal_server_error }
    end
  end

  # Process a webhook event from PayPal
  def process_webhook(payload, headers)
    # Get webhook ID from restaurant settings
    webhook_id = current_restaurant.admin_settings&.dig("payment_gateway", "paypal_webhook_id")
    
    unless webhook_id.present?
      return { 
        success: false, 
        errors: ["PayPal webhook ID is not configured for this restaurant"], 
        status: :service_unavailable 
      }
    end
    
    begin
      # Verify the webhook signature
      event_type = headers["PAYPAL-TRANSMISSION-SIG"]
      event_id = headers["PAYPAL-TRANSMISSION-ID"]
      
      # Parse the payload
      event_data = JSON.parse(payload)
      
      # Process the event based on its type
      case event_data["event_type"]
      when 'PAYMENT.CAPTURE.COMPLETED'
        process_successful_payment(event_data)
      when 'PAYMENT.CAPTURE.DENIED'
        process_failed_payment(event_data)
      else
        # Log other event types but don't take specific action
        Rails.logger.info("Unhandled PayPal event type: #{event_data["event_type"]}")
      end
      
      { success: true }
    rescue JSON::ParserError => e
      { success: false, errors: ["Invalid payload: #{e.message}"], status: :bad_request }
    rescue => e
      { success: false, errors: ["An unexpected error occurred: #{e.message}"], status: :internal_server_error }
    end
  end
  
  private
  
  # Process a successful payment
  def process_successful_payment(event_data)
    # Extract the resource data
    resource = event_data["resource"]
    
    # Get the custom_id which should contain our order ID
    custom_id = resource["custom_id"]
    order_id = custom_id.gsub("order_", "") if custom_id.present?
    
    # Find the order
    order = scope_query(Order).find_by(id: order_id)
    return unless order
    
    # Update the order status
    order.update(
      status: "paid",
      payment_status: "paid",
      payment_details: order.payment_details.merge({
        paypal_capture_id: resource["id"],
        payment_method: "paypal",
        payment_status: "succeeded"
      })
    )
    
    # Create a payment record
    OrderPayment.create(
      order: order,
      amount: resource["amount"]["value"],
      payment_method: "paypal",
      status: "paid",
      transaction_id: resource["id"],
      payment_details: {
        paypal_capture_id: resource["id"],
        payment_method_details: resource
      }
    )
  end
  
  # Process a failed payment
  def process_failed_payment(event_data)
    # Extract the resource data
    resource = event_data["resource"]
    
    # Get the custom_id which should contain our order ID
    custom_id = resource["custom_id"]
    order_id = custom_id.gsub("order_", "") if custom_id.present?
    
    # Find the order
    order = scope_query(Order).find_by(id: order_id)
    return unless order
    
    # Update the order status
    order.update(
      payment_status: "failed",
      payment_details: order.payment_details.merge({
        paypal_capture_id: resource["id"],
        payment_method: "paypal",
        payment_status: "failed",
        error_message: resource["status_details"]&.dig("reason")
      })
    )
  end
end
