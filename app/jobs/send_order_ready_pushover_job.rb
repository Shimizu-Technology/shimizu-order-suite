class SendOrderReadyPushoverJob < ApplicationJob
  queue_as :notifications

  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id)
    order = Order.includes(:restaurant).find_by(id: order_id)
    return unless order
    return unless order.status == "ready"
    return unless order.restaurant.pushover_enabled?

    idempotency_key = "order_ready_notified:pushover:#{order.id}"
    return if Rails.cache.read(idempotency_key)

    message = "Order ##{order.order_number.presence || order.id} is now ready for pickup!\n\n"
    message += "Customer: #{order.contact_name}\n" if order.contact_name.present?
    message += "Phone: #{order.contact_phone}" if order.contact_phone.present?

    order.restaurant.send_pushover_notification(
      message,
      "Order Ready for Pickup",
      {
        priority: 1,
        sound: "siren"
      }
    )

    Rails.cache.write(idempotency_key, true, expires_in: 7.days)
  end
end
