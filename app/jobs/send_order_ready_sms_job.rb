class SendOrderReadySmsJob < ApplicationJob
  queue_as :sms

  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id, sms_sender)
    order = Order.find_by(id: order_id)
    return unless order
    return unless order.status == "ready"
    return unless order.contact_phone.present?

    idempotency_key = "order_ready_notified:sms:#{order.id}"
    return if Rails.cache.read(idempotency_key)

    msg = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.order_number.presence || order.id} " \
          "is now ready for pickup! Thank you for choosing #{order.restaurant.name}."

    SendSmsJob.perform_now(to: order.contact_phone, body: msg, from: sms_sender)
    Rails.cache.write(idempotency_key, true, expires_in: 7.days)
  end
end
