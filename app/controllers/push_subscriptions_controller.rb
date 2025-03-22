class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!, only: [:index, :destroy]
  before_action :set_restaurant
  
  # GET /api/push_subscriptions
  # List all push subscriptions for the current restaurant (admin only)
  def index
    authorize! :manage, @restaurant
    
    subscriptions = @restaurant.push_subscriptions.active
    
    render json: {
      subscriptions: subscriptions.map { |sub| 
        {
          id: sub.id,
          endpoint: sub.endpoint,
          user_agent: sub.user_agent,
          created_at: sub.created_at
        }
      }
    }
  end
  
  # POST /api/push_subscriptions
  # Create a new push subscription
  def create
    # Extract subscription details from params
    subscription_params = params.require(:subscription)
    
    # Create or update the subscription
    subscription = @restaurant.push_subscriptions.find_or_initialize_by(
      endpoint: subscription_params[:endpoint]
    )
    
    subscription.p256dh_key = subscription_params[:keys][:p256dh]
    subscription.auth_key = subscription_params[:keys][:auth]
    subscription.user_agent = request.user_agent
    subscription.active = true
    
    if subscription.save
      render json: { status: 'success', id: subscription.id }
    else
      render json: { status: 'error', errors: subscription.errors.full_messages }, status: :unprocessable_entity
    end
  end
  
  # DELETE /api/push_subscriptions/:id
  # Delete a push subscription (admin only)
  def destroy
    authorize! :manage, @restaurant
    
    subscription = @restaurant.push_subscriptions.find(params[:id])
    subscription.deactivate!
    
    render json: { status: 'success' }
  end
  
  # POST /api/push_subscriptions/unsubscribe
  # Unsubscribe the current device
  def unsubscribe
    subscription_params = params.require(:subscription)
    
    subscription = @restaurant.push_subscriptions.find_by(
      endpoint: subscription_params[:endpoint]
    )
    
    if subscription
      subscription.deactivate!
      render json: { status: 'success' }
    else
      render json: { status: 'error', message: 'Subscription not found' }, status: :not_found
    end
  end
  
  # GET /api/push_subscriptions/vapid_public_key
  # Get the VAPID public key for the current restaurant
  def vapid_public_key
    if @restaurant.web_push_enabled?
      render json: { 
        vapid_public_key: @restaurant.web_push_vapid_keys[:public_key],
        enabled: true
      }
    else
      render json: { enabled: false }
    end
  end
  
  private
  
  def set_restaurant
    @restaurant = current_restaurant
  end
end
