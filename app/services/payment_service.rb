# app/services/payment_service.rb
class PaymentService
  # Generate client token for specific restaurant
  def self.generate_client_token(restaurant)
    # Check if test mode is enabled
    if restaurant.admin_settings&.dig('payment_gateway', 'test_mode') == true
      # Return a dummy token for test mode
      return "fake-client-token-#{SecureRandom.hex(8)}"
    end

    # Get a gateway instance for this restaurant
    gateway = braintree_gateway_for(restaurant)
    
    # Generate a real client token
    gateway.client_token.generate
  end

  # Process payment for specific restaurant
  def self.process_payment(restaurant, amount, payment_method_nonce)
    # Check if test mode is enabled
    if restaurant.admin_settings&.dig('payment_gateway', 'test_mode') == true
      # Return a simulated successful response for testing
      return OpenStruct.new(
        success?: true,
        transaction: OpenStruct.new(
          id: "TEST-#{SecureRandom.hex(10)}",
          status: "authorized",
          amount: amount
        )
      )
    end

    # Get a gateway instance for this restaurant
    gateway = braintree_gateway_for(restaurant)
    
    # Process the real payment
    gateway.transaction.sale(
      amount: amount,
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
          status: "settled",
          amount: "0.00",
          created_at: Time.current,
          updated_at: Time.current
        )
      )
    end

    # Get a gateway instance for this restaurant
    gateway = braintree_gateway_for(restaurant)
    
    # Find the transaction
    gateway.transaction.find(transaction_id)
  end

  private

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
