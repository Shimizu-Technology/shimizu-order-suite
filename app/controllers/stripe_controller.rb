class StripeController < ApplicationController
  include RestaurantScope

  # Mark these as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?(['create_intent', 'webhook'])
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
        # If the payment is associated with an order, you might want to update the order status
        order = Order.find_by(payment_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'paid',
            payment_method: 'stripe'
          )
        end
        
      when 'payment_intent.payment_failed'
        payment_intent = event['data']['object']
        
        # Handle failed payment
        order = Order.find_by(payment_id: payment_intent.id)
        if order
          order.update(
            payment_status: 'failed',
            payment_method: 'stripe'
          )
        end
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
    Restaurant.find_by(id: params[:restaurant_id])
  end
  
  def render_not_found
    render json: { error: 'Restaurant not found' }, status: :not_found
  end
end
