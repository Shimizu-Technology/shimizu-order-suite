# app/models/tenant_event.rb
#
# The TenantEvent model stores events related to tenant activity for analytics
# and monitoring purposes. Each event is associated with a specific restaurant (tenant)
# and contains event-specific data stored in a JSONB column.
#
class TenantEvent < ApplicationRecord
  # Associations
  belongs_to :restaurant
  
  # Validations
  validates :restaurant_id, presence: true
  validates :event_type, presence: true
  
  # Scopes
  scope :recent, -> { order(created_at: :desc).limit(100) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :in_timeframe, ->(start_time, end_time) { where(created_at: start_time..end_time) }
  
  # Store event data as JSON
  store :data, coder: JSON
  
  # Class methods for common event types
  class << self
    def log_api_request(restaurant, controller, action, duration, status, user_id = nil)
      create!(
        restaurant_id: restaurant.id,
        event_type: 'api_request',
        data: {
          controller: controller,
          action: action,
          duration_ms: duration,
          status: status,
          user_id: user_id
        }
      )
    end
    
    def log_error(restaurant, error_type, details = {})
      create!(
        restaurant_id: restaurant.id,
        event_type: 'error',
        data: {
          error_type: error_type,
          details: details
        }
      )
    end
    
    def log_user_activity(restaurant, user, activity_type, details = {})
      create!(
        restaurant_id: restaurant.id,
        event_type: 'user_activity',
        data: {
          user_id: user.id,
          activity_type: activity_type,
          details: details
        }
      )
    end
    
    def log_resource_change(restaurant, resource_type, resource_id, change_type, changes = {})
      create!(
        restaurant_id: restaurant.id,
        event_type: 'resource_change',
        data: {
          resource_type: resource_type,
          resource_id: resource_id,
          change_type: change_type, # created, updated, deleted
          changes: changes
        }
      )
    end
  end
  
  # Instance methods
  
  # Return a human-readable summary of the event
  def summary
    case event_type
    when 'api_request'
      "API Request to #{data['controller']}##{data['action']} (#{data['status']})"
    when 'error'
      "Error: #{data['error_type']}"
    when 'user_activity'
      "User #{data['user_id']} performed #{data['activity_type']}"
    when 'resource_change'
      "#{data['change_type'].capitalize} #{data['resource_type']} ##{data['resource_id']}"
    else
      "#{event_type} event"
    end
  end
  
  # Return the severity level of the event
  def severity
    case event_type
    when 'error'
      'high'
    when 'api_request'
      data['status'].to_s.start_with?('5') ? 'high' : 'low'
    when 'resource_change'
      data['change_type'] == 'deleted' ? 'medium' : 'low'
    else
      'low'
    end
  end
end
