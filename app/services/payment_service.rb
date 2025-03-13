# app/services/payment_service.rb
class PaymentService
  # Generate client token for specific restaurant
  def self.generate_client_token(restaurant)
    # Check if test mode is enabled
    if restaurant.admin_settings&.dig('payment_gateway', 'test_mode') == true
      # Return a dummy token for test mode
      return "fake-client-token-#{SecureRandom.hex(8)}"
    end

    # Get credentials from restaurant's admin_settings
    credentials = restaurant.admin_settings&.dig('payment_gateway') || {}
    payment_processor = credentials['payment_processor'] || 'paypal'
    
    if payment_processor == 'stripe'
      # For Stripe, we return the publishable key
      return credentials['publishable_key']
    else
      # For PayPal, we just return the client ID as the token
      # This will be used to initialize the PayPal SDK on the frontend
      return credentials['client_id']
    end
  end

  # Create an order for specific restaurant
  def self.create_order(restaurant, amount)
    # Check if test mode is enabled
    if restaurant.admin_settings&.dig('payment_gateway', 'test_mode') == true
      # Return a simulated successful response for testing
      return OpenStruct.new(
        success?: true,
        order_id: "TEST-ORDER-#{SecureRandom.hex(10)}"
      )
    end

    # Get a PayPal client instance for this restaurant
    client = paypal_client_for(restaurant)
    
    # Create the order request
    request = PayPalCheckoutSdk::Orders::OrdersCreateRequest.new
    request.prefer("return=representation")
    request.request_body({
      intent: 'CAPTURE',
      purchase_units: [{
        amount: {
          currency_code: 'USD',
          value: amount.to_s
        }
      }]
    })
    
    begin
      # Execute the request
      response = client.execute(request)
      
      # Return a success response
      OpenStruct.new(
        success?: true,
        order_id: response.result.id
      )
    rescue => e
      # Return a failure response
      Rails.logger.error("PayPal create_order error: #{e.message}")
      OpenStruct.new(
        success?: false,
        message: e.message
      )
    end
  end

  # Process payment for specific restaurant
  def self.process_payment(restaurant, payment_method_nonce, order_id = nil)
    # Check if test mode is enabled
    if restaurant.admin_settings&.dig('payment_gateway', 'test_mode') == true
      # Return a simulated successful response for testing
      return OpenStruct.new(
        success?: true,
        transaction: OpenStruct.new(
          id: "TEST-#{SecureRandom.hex(10)}",
          status: "COMPLETED",
          amount: payment_method_nonce # In test mode, we're passing amount as the nonce
        )
      )
    end

    # Get credentials from restaurant's admin_settings
    credentials = restaurant.admin_settings&.dig('payment_gateway') || {}
    payment_processor = credentials['payment_processor'] || 'paypal'

    if payment_processor == 'stripe'
      # For Stripe payments, payment_method_nonce will be the payment intent ID
      # and order_id will be null
      return stripe_process_payment(restaurant, payment_method_nonce)
    else
      # If we're using the old Braintree flow, delegate to braintree_process_payment
      unless order_id
        return braintree_process_payment(restaurant, payment_method_nonce)
      end

      # Otherwise, use PayPal flow
      # Get a PayPal client instance for this restaurant
      client = paypal_client_for(restaurant)
      
      # Create the capture request
      request = PayPalCheckoutSdk::Orders::OrdersCaptureRequest.new(order_id)
      
      begin
        # Execute the request
        response = client.execute(request)
        
        # Extract amount from response
        amount = nil
        if response.result.purchase_units && !response.result.purchase_units.empty?
          # Since we're using a mock, we need to handle this differently
          amount = response.result.purchase_units[0].amount&.value rescue "0.00"
        end
        
        # Return a success response
        OpenStruct.new(
          success?: true,
          transaction: OpenStruct.new(
            id: response.result.id,
            status: response.result.status,
            amount: amount
          )
        )
      rescue => e
        # Return a failure response
        Rails.logger.error("PayPal process_payment error: #{e.message}")
        OpenStruct.new(
          success?: false,
          message: e.message
        )
      end
    end
  end

  # For backwards compatibility with Braintree
  def self.braintree_process_payment(restaurant, payment_method_nonce)
    # Get a gateway instance for this restaurant
    gateway = braintree_gateway_for(restaurant)
    
    # Process the real payment
    gateway.transaction.sale(
      amount: payment_method_nonce, # In the old flow, this is actually the amount
      payment_method_nonce: payment_method_nonce,
      options: { submit_for_settlement: true }
    )
  end

  # Get transaction details
  def self.find_transaction(restaurant, transaction_id)
    # Check if it's a test transaction
    if transaction_id.start_with?('TEST-')
      # Return a simulated transaction for testing
      return OpenStruct.new(
        success?: true,
        transaction: OpenStruct.new(
          id: transaction_id,
          status: "COMPLETED",
          amount: "0.00",
          created_at: Time.current,
          updated_at: Time.current
        )
      )
    end

    # Get credentials from restaurant's admin_settings
    credentials = restaurant.admin_settings&.dig('payment_gateway') || {}
    payment_processor = credentials['payment_processor'] || 'paypal'

    # Check if it's a Stripe payment intent
    if payment_processor == 'stripe' && transaction_id.start_with?('pi_')
      return find_stripe_transaction(restaurant, transaction_id)
    # Try to find the transaction using PayPal 
    elsif transaction_id.length > 10 # This is probably a PayPal order ID
      return find_paypal_transaction(restaurant, transaction_id)
    else
      # Fall back to Braintree if it looks like a Braintree transaction ID
      return find_braintree_transaction(restaurant, transaction_id)
    end
  end

  # Find a PayPal transaction
  def self.find_paypal_transaction(restaurant, transaction_id)
    # Get a PayPal client instance for this restaurant
    client = paypal_client_for(restaurant)
    
    # Create the get order request
    request = PayPalCheckoutSdk::Orders::OrdersGetRequest.new(transaction_id)
    
    begin
      # Execute the request
      response = client.execute(request)
      
      # Extract amount from response (for the mock implementation)
      amount = "0.00"
      create_time = Time.current.iso8601
      update_time = Time.current.iso8601
      
      if response.result.purchase_units && !response.result.purchase_units.empty?
        amount = response.result.purchase_units[0].amount&.value rescue "0.00"
      end
      
      # Return a success response
      OpenStruct.new(
        success?: true,
        transaction: OpenStruct.new(
          id: response.result.id,
          status: response.result.status,
          amount: amount,
          created_at: Time.parse(create_time),
          updated_at: Time.parse(update_time)
        )
      )
    rescue => e
      # Return a failure response
      Rails.logger.error("PayPal find_transaction error: #{e.message}")
      OpenStruct.new(
        success?: false,
        message: e.message
      )
    end
  end

  # Find a Braintree transaction
  def self.find_braintree_transaction(restaurant, transaction_id)
    # Get a gateway instance for this restaurant
    gateway = braintree_gateway_for(restaurant)
    
    # Find the transaction
    gateway.transaction.find(transaction_id)
  end

  # Process a Stripe payment
  def self.stripe_process_payment(restaurant, payment_intent_id)
    begin
      # Get credentials from restaurant's admin_settings
      credentials = restaurant.admin_settings&.dig('payment_gateway') || {}
      secret_key = credentials['secret_key']
      
      # Initialize Stripe with the restaurant's API key
      Stripe.api_key = secret_key
      
      # Retrieve the payment intent
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      
      # Return the payment intent details
      return OpenStruct.new(
        success?: true,
        transaction: OpenStruct.new(
          id: payment_intent.id,
          status: payment_intent.status,
          amount: (payment_intent.amount / 100.0).to_s # Convert from cents to dollars
        )
      )
    rescue Stripe::StripeError => e
      # Return a failure response
      Rails.logger.error("Stripe process_payment error: #{e.message}")
      return OpenStruct.new(
        success?: false,
        message: e.message
      )
    rescue => e
      # Return a generic failure response
      Rails.logger.error("Stripe process_payment error: #{e.message}")
      return OpenStruct.new(
        success?: false,
        message: "An unexpected error occurred"
      )
    end
  end

  # Find a Stripe transaction
  def self.find_stripe_transaction(restaurant, payment_intent_id)
    begin
      # Get credentials from restaurant's admin_settings
      credentials = restaurant.admin_settings&.dig('payment_gateway') || {}
      secret_key = credentials['secret_key']
      
      # Initialize Stripe with the restaurant's API key
      Stripe.api_key = secret_key
      
      # Retrieve the payment intent
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      
      # Return a success response
      return OpenStruct.new(
        success?: true,
        transaction: OpenStruct.new(
          id: payment_intent.id,
          status: payment_intent.status,
          amount: (payment_intent.amount / 100.0).to_s, # Convert from cents to dollars
          created_at: Time.at(payment_intent.created),
          updated_at: payment_intent.canceled_at ? Time.at(payment_intent.canceled_at) : Time.current
        )
      )
    rescue Stripe::StripeError => e
      # Return a failure response
      Rails.logger.error("Stripe find_transaction error: #{e.message}")
      return OpenStruct.new(
        success?: false,
        message: e.message
      )
    rescue => e
      # Return a generic failure response
      Rails.logger.error("Stripe find_transaction error: #{e.message}")
      return OpenStruct.new(
        success?: false,
        message: "An unexpected error occurred"
      )
    end
  end

  private

  # Create a PayPal client for a specific restaurant
  def self.paypal_client_for(restaurant)
    # Get credentials from restaurant's admin_settings
    credentials = restaurant.admin_settings&.dig('payment_gateway') || {}
    
    # Determine environment
    environment = credentials['environment'] == 'production' ? 
      PayPal::LiveEnvironment.new(credentials['client_id'], credentials['client_secret']) :
      PayPal::SandboxEnvironment.new(credentials['client_id'], credentials['client_secret'])
    
    # Create a client
    PayPal::PayPalHttpClient.new(environment)
  end

  # Create a Braintree gateway instance for a specific restaurant
  def self.braintree_gateway_for(restaurant)
    # Get credentials from restaurant's admin_settings
    credentials = restaurant.admin_settings&.dig('payment_gateway') || {}
    
    # Create a gateway with the restaurant's credentials
    Braintree::Gateway.new(
      environment: (credentials['environment'] || 'sandbox').to_sym,
      merchant_id: credentials['merchant_id'],
      public_key: credentials['public_key'],
      private_key: credentials['private_key']
    )
  end
end
