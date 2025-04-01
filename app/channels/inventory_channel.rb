class InventoryChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info("InventoryChannel subscription attempt - " + {
      user_id: current_user.id,
      email: current_user.email,
      restaurant_id: restaurant_id,
      connection_id: connection.connection_identifier,
      subscription_id: identifier,
      client_ip: connection.env['REMOTE_ADDR'],
      user_agent: connection.env['HTTP_USER_AGENT']
    }.to_json)

    if restaurant_id.present?
      channel_name = "inventory_channel_#{restaurant_id}"
      begin
        stream_from channel_name
        Rails.logger.info("InventoryChannel subscription successful - " + {
          channel: channel_name,
          user_id: current_user.id,
          restaurant_id: restaurant_id,
          subscription_id: identifier,
          subscribed_at: Time.current.iso8601
        }.to_json)
      rescue => e
        Rails.logger.error("InventoryChannel stream creation failed - " + {
          channel: channel_name,
          user_id: current_user.id,
          error: e.message,
          backtrace: e.backtrace&.first(5)
        }.to_json)
        reject
      end
    else
      Rails.logger.error("InventoryChannel subscription rejected - " + {
        reason: "No restaurant_id available",
        user_id: current_user.id,
        connection_id: connection.connection_identifier
      }.to_json)
      reject
    end
  end

  def unsubscribed
    Rails.logger.info("InventoryChannel unsubscribed - " + {
      user_id: current_user&.id,
      restaurant_id: restaurant_id,
      connection_id: connection.connection_identifier,
      subscription_id: identifier,
      duration: ((Time.current - subscription_start_time).round(2) rescue 'unknown'),
      reason: params[:reason]
    }.to_json)
  end

  private

  def subscription_start_time
    @subscription_start_time ||= Time.current
  end
end