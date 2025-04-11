# app/controllers/notifications_controller.rb
class NotificationsController < ApplicationController
  include TenantIsolation

  before_action :authorize_request
  before_action :require_admin_or_super_admin

  # GET /notifications/unacknowledged
  # Retrieves unacknowledged notifications
  # Params:
  #   - type: Filter by notification type (optional)
  #   - hours: Only get notifications from the last X hours (default: 24)
  def unacknowledged
    result = notification_service.unacknowledged_notifications(params, current_user)
    
    if result[:success]
      # Ensure we're returning an array
      notifications_array = result[:notifications].to_a
      
      # Add debug logging
      Rails.logger.debug("Notifications response - " + {
        count: notifications_array.length,
        type: params[:type],
        hours: params[:hours].present? ? params[:hours].to_i : 24,
        is_array: notifications_array.is_a?(Array),
        first_notification: notifications_array.first&.as_json,
        response_type: 'array'
      }.to_json)
      
      # Explicitly render as array
      render json: { notifications: notifications_array }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end

  # POST /notifications/:id/acknowledge
  # Acknowledges a single notification
  def acknowledge
    result = notification_service.acknowledge_notification(params[:id], current_user)
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /notifications/:id/take_action
  # Takes action on a notification based on its type and the action requested
  # Params:
  #   - action_type: Type of action to take (e.g., 'restock')
  #   - quantity: For restock actions, the quantity to add
  def take_action
    result = notification_service.take_action_on_notification(params[:id], params, current_user)
    
    if result[:success]
      render json: {
        success: true,
        message: result[:message],
        notification: result[:notification],
        variant: result[:variant]
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  # POST /notifications/acknowledge_all
  # Acknowledges all unacknowledged notifications matching parameters
  # Params:
  #   - type: Only acknowledge notifications of this type (optional)
  def acknowledge_all
    result = notification_service.acknowledge_all_notifications(params, current_user)
    
    if result[:success]
      render json: { acknowledged_count: result[:acknowledged_count] }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def require_admin_or_super_admin
    unless current_user && current_user.role.in?(%w[admin super_admin staff])
      render json: { error: "Unauthorized - Admin access required" }, status: :forbidden
    end
  end

  def notification_service
    @notification_service ||= NotificationService.new(current_restaurant, analytics)
  end
end
