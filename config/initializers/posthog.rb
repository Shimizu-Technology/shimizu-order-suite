# Initialize PostHog client
require 'posthog-ruby'

POSTHOG_CLIENT = PostHog::Client.new({
  api_key: ENV['POSTHOG_API_KEY'],
  host: ENV['POSTHOG_HOST'],
  on_error: Proc.new { |status, msg| Rails.logger.error("[PostHog Error] #{status}: #{msg}") }
})
