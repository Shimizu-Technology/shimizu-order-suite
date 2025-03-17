# frozen_string_literal: true

require "paypal-checkout-sdk"

module PaypalHelper
  def self.environment
    if Rails.env.production? && ENV["PAYPAL_ENVIRONMENT"] == "production"
      # Production environment
      PayPal::LiveEnvironment.new(
        ENV["PAYPAL_CLIENT_ID"],
        ENV["PAYPAL_CLIENT_SECRET"]
      )
    else
      # Sandbox environment for development, test, and staging
      PayPal::SandboxEnvironment.new(
        ENV["PAYPAL_CLIENT_ID"] || "sandbox-client-id",
        ENV["PAYPAL_CLIENT_SECRET"] || "sandbox-client-secret"
      )
    end
  end

  def self.client
    PayPal::PayPalHttpClient.new(environment)
  end
end
