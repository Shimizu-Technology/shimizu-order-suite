# app/models/notification_template.rb
class NotificationTemplate < ApplicationRecord
  belongs_to :restaurant, optional: true # nil means system default
  
  validates :notification_type, presence: true
  validates :channel, presence: true, inclusion: { in: %w[email sms whatsapp] }
  validates :content, presence: true
  validates :frontend_id, allow_nil: true, length: { maximum: 255 }
  
  # Email-specific validations
  validates :subject, presence: true, if: -> { channel == 'email' }
  
  # Scope to find templates for a specific restaurant, falling back to defaults
  def self.find_for_restaurant(notification_type, channel, restaurant_id)
    # Try to find restaurant-specific template
    template = where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: restaurant_id,
      active: true
    ).first
    
    # Fall back to default template if not found
    template || where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: nil,
      active: true
    ).first
  end
  
  # Find a template for a specific restaurant and frontend, with fallbacks
  def self.find_for_restaurant_and_frontend(notification_type, channel, restaurant_id, frontend_id)
    # Try to find restaurant-specific template for this frontend
    template = where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: restaurant_id,
      frontend_id: frontend_id,
      active: true
    ).first
    
    # Fall back to restaurant-specific template without frontend_id
    template ||= where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: restaurant_id,
      frontend_id: nil,
      active: true
    ).first
    
    # Fall back to default template for this frontend
    template ||= where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: nil,
      frontend_id: frontend_id,
      active: true
    ).first
    
    # Fall back to default template without frontend_id
    template ||= where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: nil,
      frontend_id: nil,
      active: true
    ).first
  end
  
  # Clone a default template for a specific restaurant
  def self.clone_for_restaurant(notification_type, channel, restaurant_id, frontend_id = nil)
    # Try to find a default template for this frontend
    default_template = where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: nil,
      frontend_id: frontend_id
    ).first
    
    # Fall back to default template without frontend_id
    default_template ||= where(
      notification_type: notification_type,
      channel: channel,
      restaurant_id: nil,
      frontend_id: nil
    ).first
    
    return nil unless default_template
    
    # Create a new template based on the default
    create(
      notification_type: default_template.notification_type,
      channel: default_template.channel,
      subject: default_template.subject,
      content: default_template.content,
      sender_name: default_template.sender_name,
      restaurant_id: restaurant_id,
      frontend_id: frontend_id,
      active: true
    )
  end
end
