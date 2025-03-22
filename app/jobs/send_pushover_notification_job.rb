# app/jobs/send_pushover_notification_job.rb
class SendPushoverNotificationJob < ApplicationJob
  queue_as :notifications

  # More important than web push, but can expire after 6 hours
  sidekiq_options retry: 5, expires_in: 6.hours

  # Send a notification to Pushover
  # @param restaurant_id [Integer] The ID of the restaurant to send the notification to
  # @param message [String] The message body
  # @param title [String] The notification title (optional)
  # @param priority [Integer] The notification priority (-2 to 2, default 0)
  # @param sound [String] The sound to play (optional)
  # @param url [String] A URL to include (optional)
  # @param url_title [String] The title for the URL (optional)
  def perform(restaurant_id, message, title: nil, priority: 0, sound: nil, url: nil, url_title: nil)
    # Add logging to debug the job execution
    Rails.logger.info("Executing SendPushoverNotificationJob for restaurant_id: #{restaurant_id}")
    Rails.logger.info("Message: #{message}")
    Rails.logger.info("Title: #{title}")
    Rails.logger.info("Priority: #{priority}")
    Rails.logger.info("Sound: #{sound}")
    
    # Find the restaurant
    restaurant = Restaurant.find_by(id: restaurant_id)
    
    # Return if restaurant not found or no Pushover keys are set
    unless restaurant
      Rails.logger.error("Restaurant not found with ID: #{restaurant_id}")
      return
    end
    
    unless restaurant.pushover_enabled?
      Rails.logger.info("Pushover is not enabled for restaurant: #{restaurant.id} - #{restaurant.name}")
      return
    end
    
    # Get the user key from the restaurant
    user_key = restaurant.pushover_recipient_key
    unless user_key.present?
      Rails.logger.error("No Pushover recipient key found for restaurant: #{restaurant.id} - #{restaurant.name}")
      return
    end
    
    Rails.logger.info("Sending Pushover notification to user_key: #{user_key}")
    
    # Send the notification
    result = PushoverClient.send_notification(
      user_key: user_key,
      message: message,
      title: title,
      priority: priority,
      app_token: restaurant.admin_settings&.dig("pushover", "app_token"),
      sound: sound,
      url: url,
      url_title: url_title
    )
    
    if result
      Rails.logger.info("Pushover notification sent successfully")
    else
      Rails.logger.error("Failed to send Pushover notification")
    end
  end
end
