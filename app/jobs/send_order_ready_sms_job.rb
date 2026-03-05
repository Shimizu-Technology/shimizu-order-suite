class SendOrderReadySmsJob < ApplicationJob
  queue_as :sms

  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id, sms_sender, transition_token)
    order = Order.includes(:restaurant).find_by(id: order_id)
    return unless order
    return unless order.status == "ready"
    return unless order.contact_phone.present?

    notification_channels = order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
    return unless notification_channels["sms"] == true

    idempotency_key = "order_ready_notified:sms:#{order.id}:#{transition_token}"
    return if already_notified?(idempotency_key)

    msg = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.order_number.presence || order.id} " \
          "is now ready for pickup! Thank you for choosing #{order.restaurant.name}."

    SendSmsJob.perform_now(to: order.contact_phone, body: msg, from: sms_sender)
    mark_notified(idempotency_key)
  end

  private

  def already_notified?(key)
    Rails.cache.read(key)
  rescue StandardError => e
    Rails.logger.warn("SMS idempotency read failed for #{key}: #{e.class} - #{e.message}")
    false
  end

  def mark_notified(key)
    Rails.cache.write(key, true, expires_in: 7.days)
  rescue StandardError => e
    Rails.logger.warn("SMS idempotency write failed for #{key}: #{e.class} - #{e.message}")
  end
end
