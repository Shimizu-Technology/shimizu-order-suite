# frozen_string_literal: true

class PaypalController < ApplicationController
  include RestaurantScope
  skip_before_action :verify_authenticity_token, only: [:create_order, :capture_order]
  before_action :validate_amount, only: [:create_order]

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
end
