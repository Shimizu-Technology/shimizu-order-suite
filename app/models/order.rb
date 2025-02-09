# app/models/order.rb

class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user, optional: true

  after_create :notify_whatsapp

  private

  def notify_whatsapp
    # Skip if in test environment or if you only want this in production
    return if Rails.env.test?

    group_id = ENV['WASSENGER_GROUP_ID']
    return unless group_id.present?

    # Format the line items nicely
    # items is an Array of Hashes like:
    #   [{ "id"=>2, "name"=>"O.M.G. Lumpia", "price"=>11.95, "quantity"=>1 }, ... ]
    item_lines = items.map do |item|
      "- #{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
    end.join("\n")

    # Build up the message
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
