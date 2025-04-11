# app/controllers/payments_controller.rb
class PaymentsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, except: [ :client_token, :process_payment, :create_order, :capture_order ]
  before_action :ensure_tenant_context

  # GET /payments/client_token
  def client_token
    result = tenant_payment_service.generate_client_token
    
    if result[:success]
      render json: { token: result[:token] }
    else
      render json: { error: result[:errors].join(', ') }, status: result[:status] || :service_unavailable
    end
  end

  # POST /payments/create_order
  def create_order
    result = tenant_payment_service.create_order(params[:amount])

    if result[:success]
      render json: {
        success: true,
        orderID: result[:order_id]
      }
    else
      render json: {
        success: false,
        error: result[:errors].join(', ')
      }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /payments/capture_order
  def capture_order
    result = tenant_payment_service.capture_order(params[:orderID])

    if result[:success]
      render json: {
        success: true,
        transaction: {
          id: result[:transaction_id],
          status: "COMPLETED",
          amount: params[:amount] || "0.00"
        }
      }
    else
      render json: {
        success: false,
        error: result[:errors].join(', ')
      }, status: result[:status] || :unprocessable_entity
    end
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
