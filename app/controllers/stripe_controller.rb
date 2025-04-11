class StripeController < ApplicationController
  include TenantIsolation
  
  before_action :ensure_tenant_context, except: [:webhook, :global_webhook]

  # Create a payment intent for Stripe
  def create_intent
    begin
      result = tenant_stripe_service.create_payment_intent(
        params[:amount],
        params[:currency] || "USD"
      )

      if result[:success]
        render json: { client_secret: result[:client_secret] }
      else
        render json: { error: result[:errors].join(', ') }, status: result[:status] || :unprocessable_entity
      end
    rescue Stripe::StripeError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      render json: { error: "An unexpected error occurred" }, status: :internal_server_error
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
      render json: { error: "An unexpected error occurred" }, status: :internal_server_error
    end
  end

  # Confirm a payment intent (if needed server-side)
  def confirm_intent
    id = params[:payment_intent_id]

    begin
      payment_intent = Stripe::PaymentIntent.retrieve(id)

      if payment_intent.status == "requires_confirmation"
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
      render json: { error: "An unexpected error occurred" }, status: :internal_server_error
    end
  end

  # Handle Stripe webhooks
  def webhook
    payload = request.body.read
    signature = request.env["HTTP_STRIPE_SIGNATURE"]
    restaurant_id = params[:restaurant_id]
    
    # Find the restaurant for this webhook
    restaurant = Restaurant.find_by(id: restaurant_id)
    
    unless restaurant
      # If no restaurant is found, use the global webhook handler
      return global_webhook
    end
    
    # Set the current restaurant context for the tenant service
    @current_restaurant = restaurant
    
    begin
      # Process the webhook using the tenant service
      result = tenant_stripe_service.process_webhook(payload, signature)
      event = result[:event]
      
      if result[:success]
        # Handle the event based on its type
        case event["type"]
        when "payment_intent.requires_action"
          payment_intent = event["data"]["object"]

          # Handle payment requiring additional authentication
          order = (Order.find_by(payment_id: payment_intent.id) ||
                  Order.find_by(transaction_id: payment_intent.id))
          if order
            order.update(
              payment_status: "requires_action",
              payment_method: "stripe",
              payment_id: payment_intent.id # Ensure payment_id is set
            )
            # You might want to notify the customer that additional action is required
          end

        when "charge.refunded"
          charge = event["data"]["object"]

          # Handle refund
          payment_intent_id = charge.payment_intent
          order = (Order.find_by(payment_id: payment_intent_id) ||
                  Order.find_by(transaction_id: payment_intent_id))
          if order
            # Check if it's a full or partial refund
            if charge.amount == charge.amount_refunded
              order.update(
                payment_status: "refunded",
                status: Order::STATUS_REFUNDED,
                refund_amount: charge.amount_refunded / 100.0, # Convert from cents
                payment_id: payment_intent_id # Ensure payment_id is set
              )
            else
              order.update(
                payment_status: "refunded",
                # No longer changing status for partial refunds
                refund_amount: charge.amount_refunded / 100.0, # Convert from cents
                payment_id: payment_intent_id # Ensure payment_id is set
              )
            end
          end

        when "charge.dispute.created"
          dispute = event["data"]["object"]

          # Handle dispute creation
          payment_intent_id = dispute.payment_intent
          order = (Order.find_by(payment_id: payment_intent_id) ||
                  Order.find_by(transaction_id: payment_intent_id))
          if order
            order.update(
              payment_status: "disputed",
              dispute_reason: dispute.reason,
              payment_id: payment_intent_id # Ensure payment_id is set
            )
            # You might want to notify administrators about the dispute
          end

        when "payment_intent.processing"
          payment_intent = event["data"]["object"]

          # Handle payment processing
          order = (Order.find_by(payment_id: payment_intent.id) ||
                  Order.find_by(transaction_id: payment_intent.id))
          if order
            order.update(
              payment_status: "processing",
              payment_method: "stripe",
              payment_id: payment_intent.id # Ensure payment_id is set
            )
          end

        when "payment_intent.canceled"
          payment_intent = event["data"]["object"]

          # Handle payment cancellation
          order = (Order.find_by(payment_id: payment_intent.id) ||
                  Order.find_by(transaction_id: payment_intent.id))
          if order
            order.update(
              payment_status: "canceled",
              payment_method: "stripe",
              payment_id: payment_intent.id # Ensure payment_id is set
            )
          end

        when "charge.dispute.updated"
          dispute = event["data"]["object"]

          # Handle dispute update
          payment_intent_id = dispute.payment_intent
          order = (Order.find_by(payment_id: payment_intent_id) ||
                  Order.find_by(transaction_id: payment_intent_id))
          if order
            # Update payment_id to ensure it's set
            order.update(payment_id: payment_intent_id) if order.payment_id.blank?
            # You might want to update dispute details or notify administrators
          end

        when "charge.dispute.closed"
          dispute = event["data"]["object"]

          # Handle dispute resolution
          payment_intent_id = dispute.payment_intent
          order = (Order.find_by(payment_id: payment_intent_id) ||
                  Order.find_by(transaction_id: payment_intent_id))
          if order
            # Update payment_id to ensure it's set
            order_updates = { payment_id: payment_intent_id }

            if dispute.status == "won"
              order_updates[:payment_status] = "paid" # Dispute resolved in your favor
            elsif dispute.status == "lost"
              order_updates[:payment_status] = "refunded" # Dispute resolved in customer's favor
            end

            order.update(order_updates)
          end

        when "payment_method.attached"
          payment_method = event["data"]["object"]

          # Handle payment method attachment
          # This is useful if you implement saved payment methods
          # You might want to associate this payment method with a customer

        when "checkout.session.completed"
          session = event["data"]["object"]

          # Handle checkout completion
          # If you use Stripe Checkout, this confirms when a checkout process is complete
          payment_intent_id = session.payment_intent
          order_id = session.metadata&.order_id
          restaurant_id = session.metadata&.restaurant_id
          
          # Find the order either by metadata or by payment_intent_id
          order = order_id.present? ? Order.find_by(id: order_id) :
                  (Order.find_by(payment_id: payment_intent_id) ||
                  Order.find_by(transaction_id: payment_intent_id))
                  
          if order
            # Find the restaurant
            restaurant = restaurant_id.present? ? Restaurant.find_by(id: restaurant_id) : order.restaurant
            
            # Update the order payment status
            order.update(
              payment_status: "paid",
              payment_method: "stripe",
              payment_id: payment_intent_id # Ensure payment_id is set
            )
            
            # Find and update any pending payment_link payments
            pending_payment = order.order_payments.find_by(payment_method: "payment_link", status: "pending")
            if pending_payment
              pending_payment.update(
                status: "paid",
                transaction_id: payment_intent_id,
                payment_id: payment_intent_id
              )
              
              # Send confirmation notification if restaurant has this setting enabled
              if restaurant&.admin_settings&.dig("notifications", "payment_confirmation")
                # Send email confirmation if we have customer email
                if pending_payment.payment_details&.dig("email").present?
                  OrderMailer.payment_confirmation(
                    pending_payment.payment_details["email"],
                    order,
                    restaurant&.name,
                    restaurant&.logo_url
                  ).deliver_later
                end
                
                # Send SMS confirmation if we have customer phone
                if pending_payment.payment_details&.dig("phone").present?
                  message = "Your payment for order ##{order.id} from #{restaurant&.name} has been received. Thank you!"
                  SendSmsJob.perform_later(pending_payment.payment_details["phone"], message, restaurant&.id)
                end
              end
            end
          end

        when "charge.succeeded"
          charge = event["data"]["object"]

          # Handle successful charge
          # This provides additional confirmation of successful charges
          payment_intent_id = charge.payment_intent
          order = (Order.find_by(payment_id: payment_intent_id) ||
                  Order.find_by(transaction_id: payment_intent_id))
          if order
            order.update(
              payment_status: "paid",
              payment_method: "stripe",
              payment_id: payment_intent_id # Ensure payment_id is set
            )
          end

        when "charge.updated"
          charge = event["data"]["object"]

          # Handle charge update
          # This notifies of any updates to charge metadata or description

        when "balance.available"
          balance = event["data"]["object"]

          # Handle balance available
          # This is useful for financial reconciliation
          # You might want to record this for accounting purposes
        else
          # Handle unknown event type
          Rails.logger.info "Unhandled event type: #{event['type']}"
        end
        
        render json: { status: "success" }
      else
        render json: { error: result[:errors].join(', ') }, status: result[:status] || :bad_request
      end
    rescue JSON::ParserError => e
      render json: { error: "Invalid payload" }, status: :bad_request
    rescue Stripe::SignatureVerificationError => e
      render json: { error: "Invalid signature" }, status: :bad_request
    rescue => e
      render json: { error: "Webhook error" }, status: :internal_server_error
    end
  end

  # Handle Stripe webhooks without requiring a restaurant_id
  def global_webhook
    payload = request.body.read
    signature = request.env["HTTP_STRIPE_SIGNATURE"]

    begin
      # Use default webhook secret from environment or credentials
      webhook_secret = Rails.configuration.stripe[:webhook_secret]
      event = Stripe::Webhook.construct_event(
        payload, signature, webhook_secret
      )

      # Handle the event
      case event["type"]
      when "payment_intent.succeeded"
        payment_intent = event["data"]["object"]

        # Handle successful payment
        # Look up the order by payment_id or transaction_id
        order = (Order.find_by(payment_id: payment_intent.id) ||
                Order.find_by(transaction_id: payment_intent.id))

        if order
          # Update order payment fields
          order.update(
            payment_status: "paid",
            payment_method: "stripe",
            payment_id: payment_intent.id, # Ensure payment_id is set
            payment_amount: payment_intent.amount / 100.0 # Convert from cents to dollars
          )

          # Create an OrderPayment record if one doesn't exist
          unless order.order_payments.exists?(payment_type: "initial")
            payment = order.order_payments.create(
              payment_type: "initial",
              amount: payment_intent.amount / 100.0, # Convert from cents to dollars
              payment_method: "stripe",
              status: "paid",
              transaction_id: payment_intent.id,
              payment_id: payment_intent.id,
              description: "Initial payment"
            )
            Rails.logger.info("Created initial payment record for order #{order.id} from global webhook: #{payment.inspect}")
          end
        end

      when "payment_intent.payment_failed"
        payment_intent = event["data"]["object"]

        # Handle failed payment
        order = (Order.find_by(payment_id: payment_intent.id) ||
                Order.find_by(transaction_id: payment_intent.id))
        if order
          order.update(
            payment_status: "failed",
            payment_method: "stripe",
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end

      when "payment_intent.requires_action"
        payment_intent = event["data"]["object"]

        # Handle payment requiring additional authentication
        order = (Order.find_by(payment_id: payment_intent.id) ||
                Order.find_by(transaction_id: payment_intent.id))
        if order
          order.update(
            payment_status: "requires_action",
            payment_method: "stripe",
            payment_id: payment_intent.id # Ensure payment_id is set
          )
          # You might want to notify the customer that additional action is required
        end

      when "charge.refunded"
        charge = event["data"]["object"]

        # Handle refund
        payment_intent_id = charge.payment_intent
        order = (Order.find_by(payment_id: payment_intent_id) ||
                Order.find_by(transaction_id: payment_intent_id))
        if order
          # Check if it's a full or partial refund
          if charge.amount == charge.amount_refunded
            order.update(
              payment_status: "refunded",
              status: Order::STATUS_REFUNDED,
              refund_amount: charge.amount_refunded / 100.0, # Convert from cents
              payment_id: payment_intent_id # Ensure payment_id is set
            )
          else
            order.update(
              payment_status: "refunded",
              # No longer changing status for partial refunds
              refund_amount: charge.amount_refunded / 100.0, # Convert from cents
              payment_id: payment_intent_id # Ensure payment_id is set
            )
          end
        end

      when "charge.dispute.created"
        dispute = event["data"]["object"]

        # Handle dispute creation
        payment_intent_id = dispute.payment_intent
        order = (Order.find_by(payment_id: payment_intent_id) ||
                Order.find_by(transaction_id: payment_intent_id))
        if order
          order.update(
            payment_status: "disputed",
            dispute_reason: dispute.reason,
            payment_id: payment_intent_id # Ensure payment_id is set
          )
          # You might want to notify administrators about the dispute
        end

      when "payment_intent.processing"
        payment_intent = event["data"]["object"]

        # Handle payment processing
        order = (Order.find_by(payment_id: payment_intent.id) ||
                Order.find_by(transaction_id: payment_intent.id))
        if order
          order.update(
            payment_status: "processing",
            payment_method: "stripe",
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end

      when "payment_intent.canceled"
        payment_intent = event["data"]["object"]

        # Handle payment cancellation
        order = (Order.find_by(payment_id: payment_intent.id) ||
                Order.find_by(transaction_id: payment_intent.id))
        if order
          order.update(
            payment_status: "canceled",
            payment_method: "stripe",
            payment_id: payment_intent.id # Ensure payment_id is set
          )
        end

      when "charge.dispute.updated"
        dispute = event["data"]["object"]

        # Handle dispute update
        payment_intent_id = dispute.payment_intent
        order = (Order.find_by(payment_id: payment_intent_id) ||
                Order.find_by(transaction_id: payment_intent_id))
        if order
          # Update payment_id to ensure it's set
          order.update(payment_id: payment_intent_id) if order.payment_id.blank?
          # You might want to update dispute details or notify administrators
        end

      when "charge.dispute.closed"
        dispute = event["data"]["object"]

        # Handle dispute resolution
        payment_intent_id = dispute.payment_intent
        order = (Order.find_by(payment_id: payment_intent_id) ||
                Order.find_by(transaction_id: payment_intent_id))
        if order
          # Update payment_id to ensure it's set
          order_updates = { payment_id: payment_intent_id }

          if dispute.status == "won"
            order_updates[:payment_status] = "paid" # Dispute resolved in your favor
          elsif dispute.status == "lost"
            order_updates[:payment_status] = "refunded" # Dispute resolved in customer's favor
            order_updates[:status] = Order::STATUS_REFUNDED
          end

          order.update(order_updates)
        end

      when "payment_method.attached"
        payment_method = event["data"]["object"]

        # Handle payment method attachment
        # This is useful if you implement saved payment methods
        # You might want to associate this payment method with a customer

      when "checkout.session.completed"
        session = event["data"]["object"]

        # Handle checkout completion
        # If you use Stripe Checkout, this confirms when a checkout process is complete
        payment_intent_id = session.payment_intent
        order_id = session.metadata&.order_id
        restaurant_id = session.metadata&.restaurant_id
        
        # Find the order either by metadata or by payment_intent_id
        order = order_id.present? ? Order.find_by(id: order_id) :
                (Order.find_by(payment_id: payment_intent_id) ||
                Order.find_by(transaction_id: payment_intent_id))
                
        if order
          # Find the restaurant
          restaurant = restaurant_id.present? ? Restaurant.find_by(id: restaurant_id) : order.restaurant
          
          # Update the order payment status
          order.update(
            payment_status: "paid",
            payment_method: "stripe",
            payment_id: payment_intent_id # Ensure payment_id is set
          )
          
          # Find and update any pending payment_link payments
          pending_payment = order.order_payments.find_by(payment_method: "payment_link", status: "pending")
          if pending_payment
            pending_payment.update(
              status: "paid",
              transaction_id: payment_intent_id,
              payment_id: payment_intent_id
            )
            
            # Send confirmation notification if restaurant has this setting enabled
            if restaurant&.admin_settings&.dig("notifications", "payment_confirmation")
              # Send email confirmation if we have customer email
              if pending_payment.payment_details&.dig("email").present?
                OrderMailer.payment_confirmation(
                  pending_payment.payment_details["email"],
                  order,
                  restaurant&.name,
                  restaurant&.logo_url
                ).deliver_later
              end
              
              # Send SMS confirmation if we have customer phone
              if pending_payment.payment_details&.dig("phone").present?
                message = "Your payment for order ##{order.id} from #{restaurant&.name} has been received. Thank you!"
                SendSmsJob.perform_later(pending_payment.payment_details["phone"], message, restaurant&.id)
              end
            end
          end
        end

      when "charge.succeeded"
        charge = event["data"]["object"]

        # Handle successful charge
        # This provides additional confirmation of successful charges
        payment_intent_id = charge.payment_intent
        order = (Order.find_by(payment_id: payment_intent_id) ||
                Order.find_by(transaction_id: payment_intent_id))
        if order
          order.update(
            payment_status: "paid",
            payment_method: "stripe",
            payment_id: payment_intent_id # Ensure payment_id is set
          )
        end

      when "charge.updated"
        charge = event["data"]["object"]

        # Handle charge update
        # This notifies of any updates to charge metadata or description

      when "balance.available"
        balance = event["data"]["object"]

        # Handle balance available
        # This is useful for financial reconciliation
        # You might want to record this for accounting purposes
      end

      render json: { status: "success" }
    rescue JSON::ParserError => e
      render json: { error: "Invalid payload" }, status: :bad_request
    rescue Stripe::SignatureVerificationError => e
      render json: { error: "Invalid signature" }, status: :bad_request
    rescue => e
      render json: { error: "Webhook error" }, status: :internal_server_error
    end
  end

  private

  def find_restaurant
    # Try to get restaurant from restaurant_id parameter
    restaurant = Restaurant.find_by(id: params[:restaurant_id])

    # If no restaurant_id parameter was provided, try to get the first restaurant
    # This is a fallback for requests that don't specify a restaurant
    restaurant ||= Restaurant.first if Restaurant.exists?

    restaurant
  end

  def render_not_found
    render json: { error: "Restaurant not found" }, status: :not_found
  end
  
  def tenant_stripe_service
    @tenant_stripe_service ||= begin
      service = TenantStripeService.new(current_restaurant)
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
