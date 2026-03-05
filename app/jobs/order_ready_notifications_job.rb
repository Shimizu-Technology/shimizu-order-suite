class OrderReadyNotificationsJob < ApplicationJob
  queue_as :default

  # Retry orchestration; per-channel jobs are idempotent and prevent duplicates.
  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id, transition_token = nil)
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

    transition_token ||= order.updated_at&.utc&.iso8601(6) || Time.current.utc.iso8601(6)

    enqueue_errors = []

    record_enqueue_error = lambda do |channel, error|
      enqueue_errors << [channel, error]
    end

    if notification_channels["email"] != false && order.contact_email.present?
      begin
        SendOrderReadyEmailJob.perform_later(order.id, transition_token)
      rescue StandardError => e
        record_enqueue_error.call("email", e)
      end
    end

    if notification_channels["sms"] == true && order.contact_phone.present?
      begin
        SendOrderReadySmsJob.perform_later(order.id, sms_sender, transition_token)
      rescue StandardError => e
        record_enqueue_error.call("sms", e)
      end
    end

    if order.restaurant.pushover_enabled?
      begin
        SendOrderReadyPushoverJob.perform_later(order.id, transition_token)
      rescue StandardError => e
        record_enqueue_error.call("pushover", e)
      end
    end

    if enqueue_errors.any?
      messages = enqueue_errors.map { |channel, error| "#{channel}=#{error.class}: #{error.message}" }.join(" | ")
      Rails.logger.error("OrderReadyNotificationsJob enqueue failures for order #{order.id}: #{messages}")
      raise enqueue_errors.first.last
    end
  end
end
