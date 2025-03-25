# Initialize PostHog client
require 'posthog-ruby'

# Only initialize PostHog if API key is present
if ENV['POSTHOG_API_KEY'].present?
  POSTHOG_CLIENT = PostHog::Client.new({
    api_key: ENV['POSTHOG_API_KEY'],
    host: ENV['POSTHOG_HOST'] || 'https://app.posthog.com',
    on_error: Proc.new { |status, msg| Rails.logger.error("[PostHog Error] #{status}: #{msg}") }
  })
  Rails.logger.info("PostHog analytics initialized")
else
  # Create a dummy client that does nothing when PostHog is not configured
  POSTHOG_CLIENT = Object.new
  
  # Define no-op methods for common PostHog operations
  [:capture, :identify, :alias, :group, :page, :flush].each do |method|
    POSTHOG_CLIENT.define_singleton_method(method) do |*args|
      # Do nothing
      true
    end
  end
  
  Rails.logger.warn("PostHog analytics disabled: POSTHOG_API_KEY not set")
end
