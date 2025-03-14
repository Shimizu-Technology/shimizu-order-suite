class StripeController < ApplicationController
  include RestaurantScope

  # Mark these as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?(['create_intent', 'webhook', 'global_webhook'])
  end
  
  # Create a payment intent for Stripe
  def create_intent
    restaurant = find_restaurant
    
    # Return 404 if restaurant not found
    return render_not_found unless restaurant
    
    # Get payment settings from restaurant
    payment_settings = restaurant.admin_settings&.dig('payment_gateway') || {}
    
    # Check if test mode is enabled
    test_mode = payment_settings['test_mode']
    
    if test_mode
      # Generate a dummy client secret in test mode
      client_secret = "pi_test_#{SecureRandom.hex(16)}_secret_#{SecureRandom.hex(16)}"
      return render json: { client_secret: client_secret }
    end
    
    # Get the amount from the request
    amount = params[:amount].to_f
    currency = params[:currency] || 'USD'
    
    # Stripe deals with amounts in cents
    amount_in_cents = (amount * 100).to_i
    
    begin
      # Create a payment intent with Stripe
      payment_intent = Stripe::PaymentIntent.create({
        amount: amount_in_cents,
        currency: currency.downcase,
        metadata: {
          restaurant_id: restaurant.id,
          test_mode: test_mode
        },
        automatic_payment_methods: {
          enabled: true
        }
      })
      
      render json: {
        client_secret: payment_intent.client_secret
      }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      render json: { error: 'An unexpected error occurred' }, status: :internal_server_error
    end
  end
  
  # Get details about a payment intent
  def payment_intent
    id = params[:id]
    
    begin
      payment_intent = Stripe::PaymentIntent.retrieve(id)
      render json: payment_intent
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      render json: { error: 'An unexpected error occurred' }, status: :internal_server_error
    end
  end
  
  # Confirm a payment intent (if needed server-side)
  def confirm_intent
    id = params[:payment_intent_id]
    
    begin
      payment_intent = Stripe::PaymentIntent.retrieve(id)
      
      if payment_intent.status == 'requires_confirmation'
        payment_intent = payment_intent.confirm
      end
      
      render json: {
        id: payment_intent.id,
        status: payment_intent.status,
        client_secret: payment_intent.client_secret
      }
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      render json: { error: 'An unexpected error occurred' }, status: :internal_server_error
    end
  end
  
  # Handle Stripe webhooks
  def webhook
    payload = request.body.read
    signature = request.env['HTTP_STRIPE_SIGNATURE']
    restaurant_id = params[:restaurant_id]
    
    begin
      event = nil
      
      # Find the restaurant
      restaurant = Restaurant.find_by(id: restaurant_id)
      
      if restaurant
        # Get the webhook secret from restaurant settings
        webhook_secret = restaurant.admin_settings&.dig('payment_gateway', 'webhook_secret')
        
        if webhook_secret.present?
          event = Stripe::Webhook.construct_event(
            payload, signature, webhook_secret
          )
        else
          # Use default webhook secret from environment or credentials
          webhook_secret = Rails.configuration.stripe[:webhook_secret]
          event = Stripe::Webhook.construct_event(
            payload, signature, webhook_secret
          )
        end
      else
        # Use default webhook secret from environment or credentials
        webhook_secret = Rails.configuration.stripe[:webhook_secret]
        event = Stripe::Webhook.construct_event(
          payload, signature, webhook_secret
        )
      end
      
      # Handle the event
      case event['type']
      when 'payment_intent.succeeded'
        payment_intent = event['data']['object']
        
        # Handle successful payment
        # Look up the order by payment_id or transaction_id
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        
        if order
          # Update order payment fields
          order.update(
            payment_status: 'paid',
            payment_method: 'stripe',
            payment_id: payment_intent.id, # Ensure payment_id is set
            payment_amount: payment_intent.amount / 100.0 # Convert from cents to dollars
          )
          
          # Create an OrderPayment record if one doesn't exist
          unless order.order_payments.exists?(payment_type: 'initial')
            payment = order.order_payments.create(
              payment_type: 'initial',
              amount: payment_intent.amount / 100.0, # Convert from cents to dollars
              payment_method: 'stripe',
              status: 'paid',
              transaction_id: payment_intent.id,
              payment_id: payment_intent.id,
              description: "Initial payment"
            )
            Rails.logger.info("Created initial payment record for order #{order.id} from webhook: #{payment.inspect}")
          end
        end
        
      when 'payment_intent.payment_failed'
        payment_intent = event['data']['object']
        
        # Handle failed payment
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'failed',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end
        
      when 'payment_intent.requires_action'
        payment_intent = event['data']['object']
        
        # Handle payment requiring additional authentication
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'requires_action',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
          # You might want to notify the customer that additional action is required
        end
        
      when 'charge.refunded'
        charge = event['data']['object']
        
        # Handle refund
        payment_intent_id = charge.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          # Check if it's a full or partial refund
          if charge.amount == charge.amount_refunded
            order.update(
              payment_status: 'refunded',
              status: Order::STATUS_REFUNDED,
              refund_amount: charge.amount_refunded / 100.0, # Convert from cents
              payment_id: payment_intent_id # Ensure payment_id is set
            )
          else
            order.update(
              payment_status: 'partially_refunded',
              status: Order::STATUS_PARTIALLY_REFUNDED,
              refund_amount: charge.amount_refunded / 100.0, # Convert from cents
              payment_id: payment_intent_id # Ensure payment_id is set
            )
          end
        end
        
      when 'charge.dispute.created'
        dispute = event['data']['object']
        
        # Handle dispute creation
        payment_intent_id = dispute.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          order.update(
            payment_status: 'disputed',
            dispute_reason: dispute.reason,
            payment_id: payment_intent_id # Ensure payment_id is set
          )
          # You might want to notify administrators about the dispute
        end
        
      when 'payment_intent.processing'
        payment_intent = event['data']['object']
        
        # Handle payment processing
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'processing',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end
        
      when 'payment_intent.canceled'
        payment_intent = event['data']['object']
        
        # Handle payment cancellation
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'canceled',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end
        
      when 'charge.dispute.updated'
        dispute = event['data']['object']
        
        # Handle dispute update
        payment_intent_id = dispute.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          # Update payment_id to ensure it's set
          order.update(payment_id: payment_intent_id) if order.payment_id.blank?
          # You might want to update dispute details or notify administrators
        end
        
      when 'charge.dispute.closed'
        dispute = event['data']['object']
        
        # Handle dispute resolution
        payment_intent_id = dispute.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          # Update payment_id to ensure it's set
          order_updates = { payment_id: payment_intent_id }
          
          if dispute.status == 'won'
            order_updates[:payment_status] = 'paid' # Dispute resolved in your favor
          elsif dispute.status == 'lost'
            order_updates[:payment_status] = 'refunded' # Dispute resolved in customer's favor
          end
          
          order.update(order_updates)
        end
        
      when 'payment_method.attached'
        payment_method = event['data']['object']
        
        # Handle payment method attachment
        # This is useful if you implement saved payment methods
        # You might want to associate this payment method with a customer
        
      when 'checkout.session.completed'
        session = event['data']['object']
        
        # Handle checkout completion
        # If you use Stripe Checkout, this confirms when a checkout process is complete
        payment_intent_id = session.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          order.update(
            payment_status: 'paid',
            payment_method: 'stripe',
            payment_id: payment_intent_id # Ensure payment_id is set
          )
        end
        
      when 'charge.succeeded'
        charge = event['data']['object']
        
        # Handle successful charge
        # This provides additional confirmation of successful charges
        payment_intent_id = charge.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          order.update(
            payment_status: 'paid',
            payment_method: 'stripe',
            payment_id: payment_intent_id # Ensure payment_id is set
          )
        end
        
      when 'charge.updated'
        charge = event['data']['object']
        
        # Handle charge update
        # This notifies of any updates to charge metadata or description
        
      when 'balance.available'
        balance = event['data']['object']
        
        # Handle balance available
        # This is useful for financial reconciliation
        # You might want to record this for accounting purposes
      end
      
      render json: { status: 'success' }
    rescue JSON::ParserError => e
      render json: { error: 'Invalid payload' }, status: :bad_request
    rescue Stripe::SignatureVerificationError => e
      render json: { error: 'Invalid signature' }, status: :bad_request
    rescue => e
      render json: { error: 'Webhook error' }, status: :internal_server_error
    end
  end
  
  # Handle Stripe webhooks without requiring a restaurant_id
  def global_webhook
    payload = request.body.read
    signature = request.env['HTTP_STRIPE_SIGNATURE']
    
    begin
      # Use default webhook secret from environment or credentials
      webhook_secret = Rails.configuration.stripe[:webhook_secret]
      event = Stripe::Webhook.construct_event(
        payload, signature, webhook_secret
      )
      
      # Handle the event
      case event['type']
      when 'payment_intent.succeeded'
        payment_intent = event['data']['object']
        
        # Handle successful payment
        # Look up the order by payment_id or transaction_id
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        
        if order
          # Update order payment fields
          order.update(
            payment_status: 'paid',
            payment_method: 'stripe',
            payment_id: payment_intent.id, # Ensure payment_id is set
            payment_amount: payment_intent.amount / 100.0 # Convert from cents to dollars
          )
          
          # Create an OrderPayment record if one doesn't exist
          unless order.order_payments.exists?(payment_type: 'initial')
            payment = order.order_payments.create(
              payment_type: 'initial',
              amount: payment_intent.amount / 100.0, # Convert from cents to dollars
              payment_method: 'stripe',
              status: 'paid',
              transaction_id: payment_intent.id,
              payment_id: payment_intent.id,
              description: "Initial payment"
            )
            Rails.logger.info("Created initial payment record for order #{order.id} from global webhook: #{payment.inspect}")
          end
        end
        
      when 'payment_intent.payment_failed'
        payment_intent = event['data']['object']
        
        # Handle failed payment
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'failed',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end
        
      when 'payment_intent.requires_action'
        payment_intent = event['data']['object']
        
        # Handle payment requiring additional authentication
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'requires_action',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
          # You might want to notify the customer that additional action is required
        end
        
      when 'charge.refunded'
        charge = event['data']['object']
        
        # Handle refund
        payment_intent_id = charge.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          # Check if it's a full or partial refund
          if charge.amount == charge.amount_refunded
            order.update(
              payment_status: 'refunded',
              status: Order::STATUS_REFUNDED,
              refund_amount: charge.amount_refunded / 100.0, # Convert from cents
              payment_id: payment_intent_id # Ensure payment_id is set
            )
          else
            order.update(
              payment_status: 'partially_refunded',
              status: Order::STATUS_PARTIALLY_REFUNDED,
              refund_amount: charge.amount_refunded / 100.0, # Convert from cents
              payment_id: payment_intent_id # Ensure payment_id is set
            )
          end
        end
        
      when 'charge.dispute.created'
        dispute = event['data']['object']
        
        # Handle dispute creation
        payment_intent_id = dispute.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          order.update(
            payment_status: 'disputed',
            dispute_reason: dispute.reason,
            payment_id: payment_intent_id # Ensure payment_id is set
          )
          # You might want to notify administrators about the dispute
        end
        
      when 'payment_intent.processing'
        payment_intent = event['data']['object']
        
        # Handle payment processing
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'processing',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end
        
      when 'payment_intent.canceled'
        payment_intent = event['data']['object']
        
        # Handle payment cancellation
        order = Order.find_by(payment_id: payment_intent.id) || 
                Order.find_by(transaction_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'canceled',
            payment_method: 'stripe',
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end
        
      when 'charge.dispute.updated'
        dispute = event['data']['object']
        
        # Handle dispute update
        payment_intent_id = dispute.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          # Update payment_id to ensure it's set
          order.update(payment_id: payment_intent_id) if order.payment_id.blank?
          # You might want to update dispute details or notify administrators
        end
        
      when 'charge.dispute.closed'
        dispute = event['data']['object']
        
        # Handle dispute resolution
        payment_intent_id = dispute.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          # Update payment_id to ensure it's set
          order_updates = { payment_id: payment_intent_id }
          
          if dispute.status == 'won'
            order_updates[:payment_status] = 'paid' # Dispute resolved in your favor
          elsif dispute.status == 'lost'
            order_updates[:payment_status] = 'refunded' # Dispute resolved in customer's favor
            order_updates[:status] = Order::STATUS_REFUNDED
          end
          
          order.update(order_updates)
        end
        
      when 'payment_method.attached'
        payment_method = event['data']['object']
        
        # Handle payment method attachment
        # This is useful if you implement saved payment methods
        # You might want to associate this payment method with a customer
        
      when 'checkout.session.completed'
        session = event['data']['object']
        
        # Handle checkout completion
        # If you use Stripe Checkout, this confirms when a checkout process is complete
        payment_intent_id = session.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          order.update(
            payment_status: 'paid',
            payment_method: 'stripe',
            payment_id: payment_intent_id # Ensure payment_id is set
          )
        end
        
      when 'charge.succeeded'
        charge = event['data']['object']
        
        # Handle successful charge
        # This provides additional confirmation of successful charges
        payment_intent_id = charge.payment_intent
        order = Order.find_by(payment_id: payment_intent_id) || 
                Order.find_by(transaction_id: payment_intent_id)
        if order
          order.update(
            payment_status: 'paid',
            payment_method: 'stripe',
            payment_id: payment_intent_id # Ensure payment_id is set
          )
        end
        
      when 'charge.updated'
        charge = event['data']['object']
        
        # Handle charge update
        # This notifies of any updates to charge metadata or description
        
      when 'balance.available'
        balance = event['data']['object']
        
        # Handle balance available
        # This is useful for financial reconciliation
        # You might want to record this for accounting purposes
      end
      
      render json: { status: 'success' }
    rescue JSON::ParserError => e
      render json: { error: 'Invalid payload' }, status: :bad_request
    rescue Stripe::SignatureVerificationError => e
      render json: { error: 'Invalid signature' }, status: :bad_request
    rescue => e
      render json: { error: 'Webhook error' }, status: :internal_server_error
    end
  end
  
  private
  
  def find_restaurant
    # Try to get restaurant from restaurant_id parameter
    restaurant = Restaurant.find_by(id: params[:restaurant_id])
    
    # If no restaurant_id parameter was provided, try to get the first restaurant
    # This is a fallback for requests that don't specify a restaurant
    restaurant ||= Restaurant.first if Restaurant.exists?
    
    return restaurant
  end
  
  def render_not_found
    render json: { error: 'Restaurant not found' }, status: :not_found
  end
end
