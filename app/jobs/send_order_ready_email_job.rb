class SendOrderReadyEmailJob < ApplicationJob
  queue_as :mailers

  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id, transition_token)
    order = Order.includes(:restaurant).find_by(id: order_id)
    return unless order
    return unless order.status == "ready"

    notification_channels = order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
    return if notification_channels["email"] == false
    return unless order.contact_email.present?

    idempotency_key = "order_ready_notified:email:#{order.id}:#{transition_token}"
    return unless claim_send_slot(idempotency_key)

    OrderMailer.order_ready(order).deliver_now
  end

  private

  def claim_send_slot(key)
    Rails.cache.write(key, true, expires_in: 7.days, unless_exist: true)
  rescue StandardError => e
    Rails.logger.warn("Email idempotency claim failed for #{key}: #{e.class} - #{e.message}")
    true
  end
end
