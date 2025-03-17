# app/controllers/payments_controller.rb
class PaymentsController < ApplicationController
  before_action :authorize_request, except: [ :client_token, :process_payment, :create_order, :capture_order ]

  # Mark these as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?([ "client_token", "process_payment", "create_order", "capture_order" ])
  end

  # GET /payments/client_token
  def client_token
    # Get the restaurant (from the restaurant_id param)
    restaurant = Restaurant.find(params[:restaurant_id])

    # Generate a client token
    token = PaymentService.generate_client_token(restaurant)

    render json: { token: token }
  rescue => e
    render json: { error: "Failed to generate client token: #{e.message}" }, status: :service_unavailable
  end

  # POST /payments/create_order
  def create_order
    # Get the restaurant
    restaurant = Restaurant.find(params[:restaurant_id])

    # Check if we're in test mode
    if restaurant.admin_settings&.dig("payment_gateway", "test_mode") == true
      # Return a simulated successful response for testing
      render json: {
        success: true,
        orderID: "TEST-ORDER-#{SecureRandom.hex(10)}"
      }
      return
    end

    # Check if payment gateway is configured
    if !restaurant.admin_settings&.dig("payment_gateway", "client_id").present?
      render json: {
        error: "Payment gateway not configured and test mode is disabled"
      }, status: :service_unavailable
      return
    end

    # Create the order
    result = PaymentService.create_order(
      restaurant,
      params[:amount]
    )

    # Return the result
    if result.success?
      render json: {
        success: true,
        orderID: result.order_id
      }
    else
      render json: {
        success: false,
        message: result.message
      }, status: :unprocessable_entity
    end
  rescue => e
    render json: { error: "Order creation failed: #{e.message}" }, status: :unprocessable_entity
  end

  # POST /payments/capture_order
  def capture_order
    # Get the restaurant
    restaurant = Restaurant.find(params[:restaurant_id])

    # Check if we're in test mode
    if restaurant.admin_settings&.dig("payment_gateway", "test_mode") == true
      # Return a simulated successful response for testing
      render json: {
        success: true,
        transaction: {
          id: "TEST-#{SecureRandom.hex(10)}",
          status: "COMPLETED",
          amount: params[:amount] || "0.00"
        }
      }
      return
    end

    # Process the payment
    result = PaymentService.process_payment(
      restaurant,
      nil, # No payment method nonce for PayPal
      params[:orderID]
    )

    # Return the result
    if result.success?
      render json: {
        success: true,
        transaction: {
          id: result.transaction.id,
          status: result.transaction.status,
          amount: result.transaction.amount
        }
      }
    else
      render json: {
        success: false,
        message: result.message
      }, status: :unprocessable_entity
    end
  rescue => e
    render json: { error: "Payment processing failed: #{e.message}" }, status: :unprocessable_entity
  end

  # POST /payments/process
  def process_payment
    # Get the restaurant
    restaurant = Restaurant.find(params[:restaurant_id])

    # Check if we're in test mode
    if restaurant.admin_settings&.dig("payment_gateway", "test_mode") == true
      # Return a simulated successful response for testing
      render json: {
        success: true,
        transaction: {
          id: "TEST-#{SecureRandom.hex(10)}",
          status: "authorized",
          amount: params[:amount]
        }
      }
      return
    end

    # Check if payment gateway is configured
    if !restaurant.admin_settings&.dig("payment_gateway", "merchant_id").present? &&
       !restaurant.admin_settings&.dig("payment_gateway", "client_id").present?
      render json: {
        error: "Payment gateway not configured and test mode is disabled"
      }, status: :service_unavailable
      return
    end

    # Process the payment - this handles both Braintree and PayPal
    result = PaymentService.process_payment(
      restaurant,
      params[:payment_method_nonce] || params[:amount],
      params[:orderID]
    )

    # Return the result
    if result.success?
      render json: {
        success: true,
        transaction: {
          id: result.transaction.id,
          status: result.transaction.status,
          amount: result.transaction.amount
        }
      }
    else
      render json: {
        success: false,
        message: result.message,
        errors: (result.errors.map(&:message) rescue [])
      }, status: :unprocessable_entity
    end
  rescue => e
    render json: { error: "Payment processing failed: #{e.message}" }, status: :unprocessable_entity
  end

  # GET /payments/transaction/:id
  def transaction
    # Get the restaurant
    restaurant = Restaurant.find(params[:restaurant_id])

    # Get the transaction
    result = PaymentService.find_transaction(restaurant, params[:id])

    # Return the result
    if result.success?
      render json: {
        success: true,
        transaction: {
          id: result.transaction.id,
          status: result.transaction.status,
          amount: result.transaction.amount,
          created_at: result.transaction.created_at,
          updated_at: result.transaction.updated_at
        }
      }
    else
      render json: {
        success: false,
        message: "Transaction not found"
      }, status: :not_found
    end
  rescue => e
    render json: { error: "Failed to retrieve transaction: #{e.message}" }, status: :unprocessable_entity
  end
end
