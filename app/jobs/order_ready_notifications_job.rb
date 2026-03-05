class OrderReadyNotificationsJob < ApplicationJob
  queue_as :mailers

  # Notifications are important but should eventually stop retrying
  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id)
    order = Order.includes(:restaurant).find_by(id: order_id)
    return unless order
    return unless order.status == "ready"

    notification_channels = order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
    restaurant_name = order.restaurant.name

    # Priority: 1) Restaurant phone, 2) Admin SMS sender ID, 3) Restaurant name
    sms_sender = order.restaurant.phone_number.presence ||
                 order.restaurant.admin_settings&.dig("sms_sender_id").presence ||
                 restaurant_name

    # Format phone numbers for ClickSend (remove dashes, keep only digits)
    if sms_sender&.match?(/^[\+\d\-\s\(\)]+$/) && sms_sender.gsub(/\D/, '').length >= 10
      sms_sender = sms_sender.gsub(/\D/, '').gsub(/^1/, '')
    end

    # Send email notification
    if notification_channels["email"] != false && order.contact_email.present?
      OrderMailer.order_ready(order).deliver_later
    end

    # Send SMS notification
    if notification_channels["sms"] == true && order.contact_phone.present?
      msg = "Hi #{order.contact_name.presence || 'Customer'}, your order ##{order.order_number.presence || order.id} " \
            "is now ready for pickup! Thank you for choosing #{restaurant_name}."
      SendSmsJob.perform_later(to: order.contact_phone, body: msg, from: sms_sender)
    end

    # Send Pushover notification
    if order.restaurant.pushover_enabled?
      message = "Order ##{order.order_number.presence || order.id} is now ready for pickup!\n\n"
      message += "Customer: #{order.contact_name}\n" if order.contact_name.present?
      message += "Phone: #{order.contact_phone}" if order.contact_phone.present?

      order.restaurant.send_pushover_notification(
        message,
        "Order Ready for Pickup",
        {
          priority: 1,  # High priority to bypass quiet hours
          sound: "siren"  # Attention-grabbing sound for ready orders
        }
      )
    end
  end
end
