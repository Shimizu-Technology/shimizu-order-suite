# app/models/order.rb

class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user, optional: true

  # AUTO-SET pickup time if not provided
  before_save :set_default_pickup_time

  # After creation, we do any custom notifications
  after_create :notify_whatsapp

  # Convert total to float, add created/updated times
  def as_json(options = {})
    super(options).merge(
      'total' => total.to_f,
      'createdAt' => created_at.iso8601,
      'updatedAt' => updated_at.iso8601,

      # Add this line so the frontend gets an ISO string
      'estimatedPickupTime' => estimated_pickup_time&.iso8601,

      # If you also want these in the JSON:
      'contact_name' => contact_name,
      'contact_phone' => contact_phone,
      'contact_email' => contact_email
    )
  end

  private

  def set_default_pickup_time
    # If the order didn't pass an estimated_pickup_time, we set it automatically.
    return unless estimated_pickup_time.blank?

    # Check if any item needs 24 hours
    has_24hr_item = items.any? do |item|
      menu_item = MenuItem.find_by(id: item['id'])
      menu_item&.advance_notice_hours.to_i >= 24
    end

    if has_24hr_item
      self.estimated_pickup_time = Time.current + 24.hours
    else
      self.estimated_pickup_time = Time.current + 20.minutes
    end
  end

  def notify_whatsapp
    return if Rails.env.test?

    group_id = ENV['WASSENGER_GROUP_ID']
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

    WassengerClient.new.send_group_message(group_id, message_text)
  end
end
