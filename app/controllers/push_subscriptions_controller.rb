# app/controllers/push_subscriptions_controller.rb
class PushSubscriptionsController < ApplicationController
  include TenantIsolation
  
  before_action :authenticate_user!, only: [:index, :destroy]
  
  # Override global_access_permitted to allow certain actions without tenant context
  def global_access_permitted?
    action_name.in?(["vapid_public_key", "create", "unsubscribe"])
  end
  
  # GET /api/push_subscriptions
  # List all push subscriptions for the current restaurant (admin only)
  def index
    result = push_subscription_service.list_subscriptions(current_user)
    
    if result[:success]
      render json: { subscriptions: result[:subscriptions] }
    else
      render json: { error: result[:errors].first }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /api/push_subscriptions
  # Create a new push subscription
  def create
    # Extract subscription details from params
    subscription_params = params.require(:subscription)
    
    # Extract restaurant_id from params
    restaurant_id = params[:restaurant_id]
    
    result = push_subscription_service.create_subscription(
      subscription_params,
      request.user_agent,
      restaurant_id
    )
    
    if result[:success]
      render json: { status: 'success', id: result[:id] }
    else
      render json: { status: 'error', errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # DELETE /api/push_subscriptions/:id
  # Delete a push subscription (admin only)
  def destroy
    result = push_subscription_service.delete_subscription(params[:id], current_user)
    
    if result[:success]
      render json: { status: 'success' }
    else
      render json: { error: result[:errors].first }, status: result[:status] || :internal_server_error
    end
  end
  
  # POST /api/push_subscriptions/unsubscribe
  # Unsubscribe the current device
  def unsubscribe
    subscription_params = params.require(:subscription)
    
    # Extract restaurant_id from params
    restaurant_id = params[:restaurant_id]
    
    result = push_subscription_service.unsubscribe(subscription_params, restaurant_id)
    
    if result[:success]
      render json: { status: 'success' }
    else
      render json: { status: 'error', message: result[:errors].first }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /api/push_subscriptions/vapid_public_key
  # Get the VAPID public key for the current restaurant
  def vapid_public_key
    # Extract restaurant_id from params
    restaurant_id = params[:restaurant_id]
    
    result = push_subscription_service.get_vapid_public_key(restaurant_id)
    
    if result[:success]
      if result[:vapid_public_key].present?
        render json: { 
          vapid_public_key: result[:vapid_public_key],
          enabled: result[:enabled]
        }
      else
        render json: { enabled: false }
      end
    else
      render json: { error: result[:errors].first }, status: result[:status] || :internal_server_error
    end
  end
  
  private
  
  def push_subscription_service
    @push_subscription_service ||= PushSubscriptionService.new(current_restaurant, analytics)
  end
end
