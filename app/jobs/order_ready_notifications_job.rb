class OrderReadyNotificationsJob < ApplicationJob
  queue_as :notifications

  # Retry orchestration; per-channel jobs are idempotent and prevent duplicates.
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
    if sms_sender&.match?(/^[\+\d\-\s\(\)]+$/) && sms_sender.gsub(/\D/, "").length >= 10
      sms_sender = sms_sender.gsub(/\D/, "").gsub(/^1/, "")
    end

    if notification_channels["email"] != false && order.contact_email.present?
      begin
        SendOrderReadyEmailJob.perform_later(order.id)
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue ready email for order #{order.id}: #{e.class} - #{e.message}")
      end
    end

    if notification_channels["sms"] == true && order.contact_phone.present?
      begin
        SendOrderReadySmsJob.perform_later(order.id, sms_sender)
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue ready SMS for order #{order.id}: #{e.class} - #{e.message}")
      end
    end

    if order.restaurant.pushover_enabled?
      begin
        SendOrderReadyPushoverJob.perform_later(order.id)
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue ready Pushover for order #{order.id}: #{e.class} - #{e.message}")
      end
    end
  end
end
