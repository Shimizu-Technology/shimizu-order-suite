# app/controllers/wholesale/payments_controller.rb

module Wholesale
  class PaymentsController < ApplicationController
    before_action :find_order, only: [:create, :confirm, :refund]
    
    # POST /wholesale/orders/:order_id/payments
    # Create payment intent for order
    def create
      unless @order.pending? || @order.processing?
        return render_error("Payment cannot be created for order in status: #{@order.status}")
      end
      
      if @order.payment_complete?
        return render_error("Order is already fully paid")
      end
      
      # Get payment configuration from restaurant settings
      payment_config = get_payment_configuration
      unless payment_config
        return render_error("Payment processing is not configured for this restaurant")
      end
      
      amount_cents = @order.total_cents - @order.total_paid_cents
      
      begin
        # Create Stripe Payment Intent
        payment_intent_data = create_stripe_payment_intent(
          amount_cents: amount_cents,
          currency: 'usd',
          order: @order,
          config: payment_config
        )
        
        # Create payment record
        @payment = @order.order_payments.create!(
          amount_cents: amount_cents,
          payment_method: 'stripe',
          status: 'pending',
          stripe_payment_intent_id: payment_intent_data[:id],
          payment_data: {
            stripe_client_secret: payment_intent_data[:client_secret],
            stripe_payment_intent: payment_intent_data,
            created_via: 'wholesale_api'
          }
        )
        
        render_success(
          payment: payment_summary(@payment),
          stripe: {
            client_secret: payment_intent_data[:client_secret],
            publishable_key: payment_config[:publishable_key]
          },
          message: "Payment intent created successfully"
        )
        
      rescue StandardError => e
        Rails.logger.error("Stripe payment intent creation failed: #{e.message}")
        render_error("Payment setup failed: #{e.message}")
      end
    end
    
    # POST /wholesale/payments/:id/confirm
    # Confirm payment completion (webhook or client confirmation)
    def confirm
      @payment = @order.order_payments.find(params[:id])
      
      unless @payment.pending? || @payment.processing?
        return render_error("Payment cannot be confirmed in status: #{@payment.status}")
      end
      
      stripe_payment_intent_id = @payment.stripe_payment_intent_id
      
      begin
        # Verify payment with Stripe (in a real implementation)
        # payment_intent = Stripe::PaymentIntent.retrieve(stripe_payment_intent_id)
        
        # For now, simulate successful payment confirmation
        payment_confirmed = verify_stripe_payment_intent(
          stripe_payment_intent_id,
          get_payment_configuration
        )
        
        if payment_confirmed
          @payment.mark_as_completed!(
            transaction_id: "stripe_#{stripe_payment_intent_id}",
            stripe_charge_id: "ch_simulated_#{Time.current.to_i}"
          )
          
          render_success(
            payment: payment_summary(@payment),
            order: {
              id: @order.id,
              order_number: @order.order_number,
              status: @order.reload.status,
              payment_complete: @order.payment_complete?
            },
            message: "Payment confirmed successfully"
          )
        else
          @payment.mark_as_failed!("Payment verification failed")
          render_error("Payment verification failed")
        end
        
      rescue StandardError => e
        Rails.logger.error("Payment confirmation failed: #{e.message}")
        @payment.mark_as_failed!(e.message)
        render_error("Payment confirmation failed: #{e.message}")
      end
    end
    
    # GET /wholesale/orders/:order_id/payments
    # List payments for order
    def index
      @payments = @order.order_payments.recent
      
      render_success(
        payments: @payments.map { |payment| payment_summary(payment) },
        order: {
          id: @order.id,
          order_number: @order.order_number,
          total_paid: @order.total_paid,
          payment_complete: @order.payment_complete?
        },
        message: "Payments retrieved successfully"
      )
    end
    
    # GET /wholesale/payments/:id
    # Get specific payment details
    def show
      @payment = Wholesale::OrderPayment
        .joins(order: :restaurant)
        .where(orders: { restaurant: current_restaurant })
        .find(params[:id])
      
      render_success(
        payment: payment_detail(@payment),
        message: "Payment details retrieved successfully"
      )
    rescue ActiveRecord::RecordNotFound
      render_not_found("Payment not found")
    end
    
    # POST /wholesale/payments/:id/refund
    # Process refund
    def refund
      @payment = @order.order_payments.find(params[:id])
      
      unless @payment.can_be_refunded?
        return render_error("Payment cannot be refunded in status: #{@payment.status}")
      end
      
      refund_amount_cents = params[:amount_cents]&.to_i || @payment.amount_cents
      
      if refund_amount_cents > @payment.amount_cents
        return render_error("Refund amount cannot exceed payment amount")
      end
      
      begin
        # Process refund with Stripe (in a real implementation)
        # refund = Stripe::Refund.create({
        #   charge: @payment.stripe_charge_id,
        #   amount: refund_amount_cents
        # })
        
        # For now, simulate successful refund
        refund_payment = @payment.refund!(refund_amount_cents)
        
        render_success(
          refund: payment_summary(refund_payment),
          original_payment: payment_summary(@payment.reload),
          message: "Refund processed successfully"
        )
        
      rescue StandardError => e
        Rails.logger.error("Refund processing failed: #{e.message}")
        render_error("Refund processing failed: #{e.message}")
      end
    end
    
    # POST /wholesale/payments/webhook
    # Handle Stripe webhooks
    def webhook
      payload = request.body.read
      sig_header = request.env['HTTP_STRIPE_SIGNATURE']
      
      begin
        # Verify webhook signature (in a real implementation)
        # event = Stripe::Webhook.construct_event(payload, sig_header, webhook_secret)
        
        # For now, parse the JSON payload
        event_data = JSON.parse(payload)
        
        case event_data['type']
        when 'payment_intent.succeeded'
          handle_payment_intent_succeeded(event_data['data']['object'])
        when 'payment_intent.payment_failed'
          handle_payment_intent_failed(event_data['data']['object'])
        when 'charge.dispute.created'
          handle_charge_dispute_created(event_data['data']['object'])
        else
          Rails.logger.info("Unhandled webhook event type: #{event_data['type']}")
        end
        
        render json: { received: true }
        
      rescue JSON::ParserError => e
        Rails.logger.error("Webhook payload parsing failed: #{e.message}")
        render json: { error: "Invalid payload" }, status: 400
      rescue StandardError => e
        Rails.logger.error("Webhook processing failed: #{e.message}")
        render json: { error: "Webhook processing failed" }, status: 500
      end
    end
    
    private
    
    def find_order
      @order = Wholesale::Order
        .where(restaurant: current_restaurant, user: current_user)
        .find(params[:order_id])
    rescue ActiveRecord::RecordNotFound
      render_not_found("Order not found")
      nil
    end
    
    def get_payment_configuration
      # Get payment settings from restaurant configuration
      # This reads from the same place as PaymentSettings.tsx
      payment_gateway = current_restaurant.admin_settings&.dig('payment_gateway')
      
      return nil unless payment_gateway&.dig('payment_processor') == 'stripe'
      
      {
        publishable_key: payment_gateway['publishable_key'],
        secret_key: payment_gateway['secret_key'],
        webhook_secret: payment_gateway['webhook_secret'],
        test_mode: payment_gateway['test_mode'] || false
      }
    end
    
    def create_stripe_payment_intent(amount_cents:, currency:, order:, config:)
      # In a real implementation, this would use the Stripe SDK:
      # Stripe::PaymentIntent.create({
      #   amount: amount_cents,
      #   currency: currency,
      #   metadata: {
      #     order_id: order.id,
      #     order_number: order.order_number,
      #     fundraiser_name: order.fundraiser.name,
      #     participant_name: order.participant&.name
      #   }
      # })
      
      # For now, simulate the response
      {
        id: "pi_simulated_#{Time.current.to_i}_#{SecureRandom.hex(8)}",
        client_secret: "pi_simulated_#{Time.current.to_i}_secret_#{SecureRandom.hex(16)}",
        amount: amount_cents,
        currency: currency,
        status: 'requires_payment_method',
        metadata: {
          order_id: order.id.to_s,
          order_number: order.order_number,
          fundraiser_name: order.fundraiser.name,
          participant_name: order.participant&.name
        }
      }
    end
    
    def verify_stripe_payment_intent(payment_intent_id, config)
      # In a real implementation:
      # payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      # payment_intent.status == 'succeeded'
      
      # For now, simulate successful verification
      payment_intent_id.present? && config.present?
    end
    
    def payment_summary(payment)
      {
        id: payment.id,
        amount: payment.amount,
        amount_cents: payment.amount_cents,
        payment_method: payment.payment_method,
        status: payment.status,
        transaction_id: payment.transaction_id,
        stripe_payment_intent_id: payment.stripe_payment_intent_id,
        stripe_charge_id: payment.stripe_charge_id,
        processed_at: payment.processed_at,
        created_at: payment.created_at,
        updated_at: payment.updated_at
      }
    end
    
    def payment_detail(payment)
      {
        id: payment.id,
        amount: payment.amount,
        amount_cents: payment.amount_cents,
        payment_method: payment.payment_method,
        status: payment.status,
        transaction_id: payment.transaction_id,
        stripe_payment_intent_id: payment.stripe_payment_intent_id,
        stripe_charge_id: payment.stripe_charge_id,
        processed_at: payment.processed_at,
        payment_data: payment.payment_data,
        
        order: {
          id: payment.order.id,
          order_number: payment.order.order_number,
          customer_name: payment.order.customer_name,
          total: payment.order.total
        },
        
        can_be_refunded: payment.can_be_refunded?,
        stripe_dashboard_url: payment.stripe_dashboard_url,
        
        created_at: payment.created_at,
        updated_at: payment.updated_at
      }
    end
    
    # Webhook handlers
    def handle_payment_intent_succeeded(payment_intent)
      payment = Wholesale::OrderPayment.find_by(
        stripe_payment_intent_id: payment_intent['id']
      )
      
      if payment && payment.pending?
        payment.mark_as_completed!(
          stripe_charge_id: payment_intent.dig('charges', 'data', 0, 'id')
        )
        Rails.logger.info("Payment confirmed via webhook: #{payment.id}")
      end
    end
    
    def handle_payment_intent_failed(payment_intent)
      payment = Wholesale::OrderPayment.find_by(
        stripe_payment_intent_id: payment_intent['id']
      )
      
      if payment && !payment.failed?
        error_message = payment_intent.dig('last_payment_error', 'message') || 'Payment failed'
        payment.mark_as_failed!(error_message)
        Rails.logger.info("Payment failed via webhook: #{payment.id}")
      end
    end
    
    def handle_charge_dispute_created(charge)
      # Handle charge disputes
      payment = Wholesale::OrderPayment.find_by(stripe_charge_id: charge['id'])
      
      if payment
        payment.add_payment_data(:dispute_created, {
          dispute_id: charge.dig('dispute', 'id'),
          dispute_reason: charge.dig('dispute', 'reason'),
          created_at: Time.current
        })
        
        Rails.logger.warn("Dispute created for payment: #{payment.id}")
      end
    end
  end
end