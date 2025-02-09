# app/models/order.rb

class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user, optional: true

  after_create :notify_whatsapp

  # 1) Ensure total is a float in JSON
  def as_json(options = {})
    super(options).merge(
      # Make sure 'total' is numeric
      'total' => total.to_f,

      # If your frontend references createdAt or updatedAt, you can also add:
      'createdAt' => created_at.iso8601,
      'updatedAt' => updated_at.iso8601
    )
  end

  private

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
