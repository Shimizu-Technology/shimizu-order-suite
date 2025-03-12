# frozen_string_literal: true

module PaypalHelper
  class << self
    # Returns a configured PayPal client instance for the current environment
    def client
      client_id = Rails.application.credentials.paypal[:client_id] || ENV['PAYPAL_CLIENT_ID']
      client_secret = Rails.application.credentials.paypal[:client_secret] || ENV['PAYPAL_CLIENT_SECRET']
      
      if client_id.blank? || client_secret.blank?
        raise StandardError, "PayPal API credentials not configured. Set PAYPAL_CLIENT_ID and PAYPAL_CLIENT_SECRET."
      end
      
      environment = if Rails.application.credentials.paypal[:environment] == 'production' || ENV['PAYPAL_ENVIRONMENT'] == 'production'
                      PayPal::LiveEnvironment.new(client_id, client_secret)
                    else
                      PayPal::SandboxEnvironment.new(client_id, client_secret)
                    end
      
      PayPal::PayPalHttpClient.new(environment)
    end
  end
end
