# frozen_string_literal: true

module PaypalHelper
  class << self
    # Returns a configured PayPal client instance for the current environment
    # Accepts an optional restaurant parameter to use restaurant-specific settings
    def client(restaurant = nil)
      if restaurant&.admin_settings&.dig("payment_gateway").present?
        # Use restaurant settings
        payment_gateway = restaurant.admin_settings["payment_gateway"]
        client_id = payment_gateway["client_id"]
        client_secret = payment_gateway["client_secret"]
        environment_setting = payment_gateway["environment"] || "sandbox"
        test_mode = payment_gateway["test_mode"] != false # Default to true if not set
      else
        # Fallback to credentials or ENV variables
        client_id = Rails.application.credentials.paypal[:client_id] || ENV["PAYPAL_CLIENT_ID"]
        client_secret = Rails.application.credentials.paypal[:client_secret] || ENV["PAYPAL_CLIENT_SECRET"]
        environment_setting = Rails.application.credentials.paypal[:environment] || ENV["PAYPAL_ENVIRONMENT"] || "sandbox"
        test_mode = true
      end

      if client_id.blank? || client_secret.blank?
        raise StandardError, "PayPal API credentials not configured. Set up PayPal in admin settings or environment variables."
      end

      # If in test mode, always use sandbox environment
      if test_mode
        environment = PayPal::SandboxEnvironment.new(client_id, client_secret)
      else
        # Otherwise use the configured environment
        environment = if environment_setting == "production"
                        PayPal::LiveEnvironment.new(client_id, client_secret)
        else
                        PayPal::SandboxEnvironment.new(client_id, client_secret)
        end
      end

      PayPal::PayPalHttpClient.new(environment)
    end
  end
end
