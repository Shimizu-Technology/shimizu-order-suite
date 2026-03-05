class OrderReadyNotificationsJob < ApplicationJob
  queue_as :default

  # Retry orchestration; per-channel jobs are idempotent and prevent duplicates.
  sidekiq_options retry: 8, expires_in: 24.hours

  def perform(order_id, transition_token = nil)
    order = Order.includes(:restaurant).find_by(id: order_id)
    return unless order
    return unless order.status == "ready"

    notification_channels = order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
    transition_token ||= order.updated_at&.utc&.iso8601(6) || Time.current.utc.iso8601(6)

    sms_sender = resolve_sms_sender(order)
    enqueue_errors = []

    enqueue_channel("email", order.id, transition_token, enqueue_errors) do
      SendOrderReadyEmailJob.perform_later(order.id, transition_token)
    end if notification_channels["email"] != false && order.contact_email.present?

    enqueue_channel("sms", order.id, transition_token, enqueue_errors) do
      SendOrderReadySmsJob.perform_later(order.id, sms_sender, transition_token)
    end if notification_channels["sms"] == true && order.contact_phone.present?

    enqueue_channel("pushover", order.id, transition_token, enqueue_errors) do
      SendOrderReadyPushoverJob.perform_later(order.id, transition_token)
    end if order.restaurant.pushover_enabled?

    return if enqueue_errors.empty?

    messages = enqueue_errors.map { |channel, error| "#{channel}=#{error.class}: #{error.message}" }.join(" | ")
    Rails.logger.error("OrderReadyNotificationsJob enqueue failures for order #{order.id}: #{messages}")
    raise enqueue_errors.first.last
  end

  private

  def enqueue_channel(channel, order_id, transition_token, enqueue_errors)
    return if already_enqueued?(channel, order_id, transition_token)

    yield
    mark_enqueued(channel, order_id, transition_token)
  rescue StandardError => e
    enqueue_errors << [channel, e]
  end

  def resolve_sms_sender(order)
    sender = order.restaurant.phone_number.presence ||
             order.restaurant.admin_settings&.dig("sms_sender_id").presence ||
             order.restaurant.name

    if sender&.match?(/^[\+\d\-\s\(\)]+$/) && sender.gsub(/\D/, "").length >= 10
      sender = sender.gsub(/\D/, "").gsub(/^1/, "")
    end

    sender
  end

  def enqueue_marker_key(channel, order_id, transition_token)
    "order_ready_enqueue:#{channel}:#{order_id}:#{transition_token}"
  end

  def already_enqueued?(channel, order_id, transition_token)
    Rails.cache.read(enqueue_marker_key(channel, order_id, transition_token))
  rescue StandardError => e
    Rails.logger.warn("OrderReadyNotificationsJob enqueue marker read failed: #{e.class} - #{e.message}")
    false
  end

  def mark_enqueued(channel, order_id, transition_token)
    Rails.cache.write(enqueue_marker_key(channel, order_id, transition_token), true, expires_in: 1.day)
  rescue StandardError => e
    Rails.logger.warn("OrderReadyNotificationsJob enqueue marker write failed: #{e.class} - #{e.message}")
  end
end
