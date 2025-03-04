# app/models/order.rb

class Order < ApplicationRecord
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  belongs_to :restaurant
  belongs_to :user, optional: true
  
  # Add associations for order acknowledgments
  has_many :order_acknowledgments, dependent: :destroy
  has_many :acknowledging_users, through: :order_acknowledgments, source: :user

  # AUTO-SET pickup time if not provided
  before_save :set_default_pickup_time

  # After creation, enqueue a background job for WhatsApp notifications
  after_create :notify_whatsapp

  # Convert total to float, add created/updated times, plus userId & contact info
  def as_json(options = {})
    super(options).merge(
      'total' => total.to_f,
      'createdAt' => created_at.iso8601,
      'updatedAt' => updated_at.iso8601,
      'userId' => user_id,

      # Provide an ISO8601 string for JS
      'estimatedPickupTime' => estimated_pickup_time&.iso8601,

      # Contact fields
      'contact_name' => contact_name,
      'contact_phone' => contact_phone,
      'contact_email' => contact_email,
      
      # Add flag for orders requiring 24-hour advance notice
      'requires_advance_notice' => requires_advance_notice?,
      'max_advance_notice_hours' => max_advance_notice_hours,
      
      # Payment fields
      'payment_method' => payment_method,
      'transaction_id' => transaction_id,
      'payment_status' => payment_status,
      'payment_amount' => payment_amount.to_f
    )
  end

  # Check if this order contains any items requiring advance notice (24 hours)
  def requires_advance_notice?
    max_advance_notice_hours >= 24
  end
  
  # Get the maximum advance notice hours required by any item in this order
  def max_advance_notice_hours
    @max_advance_notice_hours ||= begin
      max_hours = 0
      items.each do |item|
        menu_item = MenuItem.find_by(id: item['id'])
        if menu_item && menu_item.advance_notice_hours.to_i > max_hours
          max_hours = menu_item.advance_notice_hours.to_i
        end
      end
      max_hours
    end
  end

  private

  def set_default_pickup_time
    return unless estimated_pickup_time.blank?

    if requires_advance_notice?
      # For orders with 24-hour notice items, set pickup time to next day at 10 AM
      tomorrow = Time.current.in_time_zone(restaurant.time_zone).tomorrow
      self.estimated_pickup_time = Time.new(
        tomorrow.year, tomorrow.month, tomorrow.day, 10, 0, 0, 
        Time.find_zone(restaurant.time_zone)&.formatted_offset || "+10:00"
      )
    else
      # For regular orders, set a default of 20 minutes
      self.estimated_pickup_time = Time.current + 20.minutes
    end
  end

  def notify_whatsapp
    return if Rails.env.test?

    # Get the WhatsApp group ID from the restaurant's admin_settings
    group_id = restaurant.admin_settings&.dig('whatsapp_group_id')
    return unless group_id.present?

    item_lines = items.map do |item|
      "- #{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
    end.join("\n")

    message_text = <<~MSG
      New order \##{id} created!

      Items:
      #{item_lines}

      Total: $#{'%.2f' % total.to_f}
      Status: #{status}

      Instructions: #{special_instructions.presence || 'none'}
    MSG

    # Instead of calling Wassenger inline, enqueue an async job:
    SendWhatsappJob.perform_later(group_id, message_text)
  end
end
