# app/services/tenant_payment_service.rb
class TenantPaymentService < TenantScopedService
  attr_accessor :current_user

  # Generate client token for the current restaurant
  def generate_client_token
    # Check if test mode is enabled
    if current_restaurant.admin_settings&.dig("payment_gateway", "test_mode") == true
      # Return a dummy token for test mode
      return { success: true, token: "fake-client-token-#{SecureRandom.hex(8)}" }
    end

    # Get credentials from restaurant's admin_settings
    credentials = current_restaurant.admin_settings&.dig("payment_gateway") || {}
    payment_processor = credentials["payment_processor"] || "paypal"

    token = if payment_processor == "stripe"
      # For Stripe, we return the publishable key
      credentials["publishable_key"]
    else
      # For PayPal, we just return the client ID as the token
      # This will be used to initialize the PayPal SDK on the frontend
      credentials["client_id"]
    end

    if token.present?
      { success: true, token: token }
    else
      { success: false, errors: ["Payment gateway not configured"], status: :service_unavailable }
    end
  rescue => e
    { success: false, errors: ["Failed to generate client token: #{e.message}"], status: :service_unavailable }
  end

  # Create an order for payment processing
  def create_order(amount)
    # Check if test mode is enabled
    if current_restaurant.admin_settings&.dig("payment_gateway", "test_mode") == true
      # Return a simulated successful response for testing
      return { 
        success: true, 
        order_id: "TEST-ORDER-#{SecureRandom.hex(10)}" 
      }
    end

    # Check if payment gateway is configured
    if !current_restaurant.admin_settings&.dig("payment_gateway", "client_id").present?
      return {
        success: false,
        errors: ["Payment gateway not configured and test mode is disabled"],
        status: :service_unavailable
      }
    end

    # Delegate to the static PaymentService for now
    # In the future, this could be refactored to use instance methods
    result = PaymentService.create_order(current_restaurant, amount)

    if result.success?
      { success: true, order_id: result.order_id }
    else
      { success: false, errors: [result.error_message], status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to create order: #{e.message}"], status: :service_unavailable }
  end

  # Capture an existing order
  def capture_order(order_id)
    # Check if test mode is enabled
    if current_restaurant.admin_settings&.dig("payment_gateway", "test_mode") == true
      # Return a simulated successful response for testing
      return { 
        success: true, 
        transaction_id: "TEST-TRANSACTION-#{SecureRandom.hex(10)}" 
      }
    end

    # Check if payment gateway is configured
    if !current_restaurant.admin_settings&.dig("payment_gateway", "client_id").present?
      return {
        success: false,
        errors: ["Payment gateway not configured and test mode is disabled"],
        status: :service_unavailable
      }
    end

    # Delegate to the static PaymentService for now
    result = PaymentService.capture_order(current_restaurant, order_id)

    if result.success?
      { 
        success: true, 
        transaction_id: result.transaction_id,
        details: result.details || {}
      }
    else
      { success: false, errors: [result.error_message], status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to capture order: #{e.message}"], status: :service_unavailable }
  end

  # Process a payment
  def process_payment(payment_method_nonce, amount)
    # Check if test mode is enabled
    if current_restaurant.admin_settings&.dig("payment_gateway", "test_mode") == true
      # Return a simulated successful response for testing
      return { 
        success: true, 
        transaction_id: "TEST-TRANSACTION-#{SecureRandom.hex(10)}" 
      }
    end

    # Check if payment gateway is configured
    if !current_restaurant.admin_settings&.dig("payment_gateway", "client_id").present?
      return {
        success: false,
        errors: ["Payment gateway not configured and test mode is disabled"],
        status: :service_unavailable
      }
    end

    # Delegate to the static PaymentService for now
    result = PaymentService.process_payment(current_restaurant, payment_method_nonce, amount)

    if result.success?
      { 
        success: true, 
        transaction_id: result.transaction_id,
        details: result.details || {}
      }
    else
      { success: false, errors: [result.error_message], status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to process payment: #{e.message}"], status: :service_unavailable }
  end
end
