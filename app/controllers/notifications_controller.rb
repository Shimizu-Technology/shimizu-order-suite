class NotificationsController < ApplicationController
  include RestaurantScope
  
  before_action :authorize_request
  before_action :require_admin_or_super_admin
  
  # GET /notifications/unacknowledged
  # Retrieves unacknowledged notifications
  # Params:
  #   - type: Filter by notification type (optional)
  #   - hours: Only get notifications from the last X hours (default: 24)
  def unacknowledged
    hours = params[:hours].present? ? params[:hours].to_i : 24
    since = hours.hours.ago
    
    query = Notification.unacknowledged.recent_first.where('created_at > ?', since)
    
    # Filter by type if specified
    if params[:type].present?
      query = query.by_type(params[:type])
    end
    
    @notifications = query.all
    
    render json: @notifications
  end
  
  # POST /notifications/:id/acknowledge
  # Acknowledges a single notification
  def acknowledge
    @notification = Notification.find(params[:id])
    
    # Make sure notification belongs to the user's restaurant
    authorize_restaurant!(@notification.restaurant_id)
    
    @notification.acknowledge!(current_user)
    
    head :no_content
  end
  
  # POST /notifications/:id/take_action
  # Takes action on a notification based on its type and the action requested
  # Params:
  #   - action_type: Type of action to take (e.g., 'restock')
  #   - quantity: For restock actions, the quantity to add
  def take_action
    @notification = Notification.find(params[:id])
    
    # Make sure notification belongs to the user's restaurant
    authorize_restaurant!(@notification.restaurant_id)
    
    if @notification.notification_type == 'low_stock' && params[:action_type] == 'restock'
      # For low stock notifications, handle restock action
      if @notification.resource_type == 'MerchandiseVariant'
        variant_id = @notification.resource_id
        variant = MerchandiseVariant.find(variant_id)
        
        quantity = params[:quantity].to_i
        if quantity > 0
          # Add stock and record the reason
          variant.add_stock!(
            quantity, 
            "Restocked from notification ##{@notification.id}", 
            current_user
          )
          
          # Acknowledge the notification
          @notification.acknowledge!(current_user)
          
          render json: {
            success: true,
            message: "Successfully added #{quantity} items to inventory",
            notification: @notification,
            variant: variant.as_json(include_stock_history: true)
          }
        else
          render json: { error: "Invalid quantity. Must be greater than 0." }, status: :unprocessable_entity
        end
      else
        render json: { error: "Unsupported resource type for restock action" }, status: :unprocessable_entity
      end
    else
      render json: { error: "Unsupported notification type or action" }, status: :unprocessable_entity
    end
  end
  
  # POST /notifications/acknowledge_all
  # Acknowledges all unacknowledged notifications matching parameters
  # Params:
  #   - type: Only acknowledge notifications of this type (optional)
  def acknowledge_all
    query = Notification.unacknowledged
    
    # Filter by type if specified
    if params[:type].present?
      query = query.by_type(params[:type])
    end
    
    # Apply restaurant scope
    query = query.where(restaurant_id: current_user.restaurant_id)
    
    count = 0
    
    # Use transaction for bulk acknowledgment
    Notification.transaction do
      query.each do |notification|
        notification.acknowledge!(current_user)
        count += 1
      end
    end
    
    render json: { acknowledged_count: count }
  end
  
  private
  
  # Define this endpoint as public for restaurant scope
  def public_endpoint?
    true
  end
  
  def require_admin_or_super_admin
    unless current_user && current_user.role.in?(%w[admin super_admin])
      render json: { error: 'Unauthorized - Admin access required' }, status: :forbidden
    end
  end
  
  def authorize_restaurant!(restaurant_id)
    unless current_user.super_admin? || current_user.restaurant_id == restaurant_id
      render json: { error: 'Not authorized for this restaurant' }, status: :forbidden
      return false
    end
    true
  end
end
