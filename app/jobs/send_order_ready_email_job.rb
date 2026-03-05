class SendOrderReadyEmailJob < ApplicationJob
  queue_as :mailers

  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order
    return unless order.status == "ready"

    idempotency_key = "order_ready_notified:email:#{order.id}"
    return if Rails.cache.read(idempotency_key)

    OrderMailer.order_ready(order).deliver_now
    Rails.cache.write(idempotency_key, true, expires_in: 7.days)
  end
end
