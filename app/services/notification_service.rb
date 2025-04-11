# app/services/notification_service.rb
class NotificationService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant = nil, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Get unacknowledged notifications with optional filtering
  def unacknowledged_notifications(params, current_user)
    begin
      hours = params[:hours].present? ? params[:hours].to_i : 24
      since = hours.hours.ago
      
      # Start with notifications for the current restaurant
      query = Notification.where(restaurant_id: current_restaurant.id)
                          .unacknowledged
                          .recent_first
                          .where("created_at > ?", since)
      
      # Filter by type if specified
      if params[:type].present?
        query = query.by_type(params[:type])
      end
      
      notifications = query.all
      
      # Track analytics
      analytics.track("notifications.viewed", {
        restaurant_id: current_restaurant.id,
        user_id: current_user.id,
        count: notifications.length,
        type: params[:type],
        hours: hours
      })
      
      { success: true, notifications: notifications }
    rescue => e
      { success: false, errors: ["Failed to retrieve notifications: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Acknowledge a specific notification
  def acknowledge_notification(id, current_user)
    begin
      notification = Notification.find_by(id: id)
      
      unless notification
        return { success: false, errors: ["Notification not found"], status: :not_found }
      end
      
      # Ensure notification belongs to the current restaurant
      unless notification.restaurant_id == current_restaurant.id
        return { success: false, errors: ["Not authorized for this notification"], status: :forbidden }
      end
      
      if notification.acknowledge!(current_user)
        # Track analytics
        analytics.track("notification.acknowledged", {
          restaurant_id: current_restaurant.id,
          user_id: current_user.id,
          notification_id: notification.id,
          notification_type: notification.notification_type
        })
        
        { success: true }
      else
        { success: false, errors: ["Failed to acknowledge notification"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to acknowledge notification: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Take action on a notification (e.g., restock for low_stock notifications)
  def take_action_on_notification(id, params, current_user)
    begin
      notification = Notification.find_by(id: id)
      
      unless notification
        return { success: false, errors: ["Notification not found"], status: :not_found }
      end
      
      # Ensure notification belongs to the current restaurant
      unless notification.restaurant_id == current_restaurant.id
        return { success: false, errors: ["Not authorized for this notification"], status: :forbidden }
      end
      
      if notification.notification_type == "low_stock" && params[:action_type] == "restock"
        # For low stock notifications, handle restock action
        if notification.resource_type == "MerchandiseVariant"
          variant_id = notification.resource_id
          variant = MerchandiseVariant.find_by(id: variant_id)
          
          unless variant
            return { success: false, errors: ["Merchandise variant not found"], status: :not_found }
          end
          
          # Ensure variant belongs to the current restaurant
          unless variant.restaurant_id == current_restaurant.id
            return { success: false, errors: ["Not authorized for this merchandise variant"], status: :forbidden }
          end
          
          quantity = params[:quantity].to_i
          if quantity > 0
            # Add stock and record the reason
            variant.add_stock!(
              quantity,
              "Restocked from notification ##{notification.id}",
              current_user
            )
            
            # Acknowledge the notification
            notification.acknowledge!(current_user)
            
            # Track analytics
            analytics.track("notification.action_taken", {
              restaurant_id: current_restaurant.id,
              user_id: current_user.id,
              notification_id: notification.id,
              notification_type: notification.notification_type,
              action_type: params[:action_type],
              quantity: quantity
            })
            
            { 
              success: true, 
              message: "Successfully added #{quantity} items to inventory",
              notification: notification,
              variant: variant.as_json(include_stock_history: true)
            }
          else
            { success: false, errors: ["Invalid quantity. Must be greater than 0."], status: :unprocessable_entity }
          end
        else
          { success: false, errors: ["Unsupported resource type for restock action"], status: :unprocessable_entity }
        end
      else
        { success: false, errors: ["Unsupported notification type or action"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to take action on notification: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Acknowledge all unacknowledged notifications matching parameters
  def acknowledge_all_notifications(params, current_user)
    begin
      query = Notification.where(restaurant_id: current_restaurant.id)
                          .unacknowledged
      
      # Filter by type if specified
      if params[:type].present?
        query = query.by_type(params[:type])
      end
      
      count = 0
      
      # Use transaction for bulk acknowledgment
      Notification.transaction do
        query.each do |notification|
          notification.acknowledge!(current_user)
          count += 1
        end
      end
      
      # Track analytics
      analytics.track("notifications.bulk_acknowledged", {
        restaurant_id: current_restaurant.id,
        user_id: current_user.id,
        count: count,
        type: params[:type]
      })
      
      { success: true, acknowledged_count: count }
    rescue => e
      { success: false, errors: ["Failed to acknowledge notifications: #{e.message}"], status: :internal_server_error }
    end
  end
end
