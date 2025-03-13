# Stripe configuration

# Initialize Stripe with API keys from environment variables or credentials
Rails.configuration.stripe = {
  publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'] || Rails.application.credentials.dig(:stripe, :publishable_key),
  secret_key: ENV['STRIPE_SECRET_KEY'] || Rails.application.credentials.dig(:stripe, :secret_key),
  webhook_secret: ENV['STRIPE_WEBHOOK_SECRET'] || Rails.application.credentials.dig(:stripe, :webhook_secret)
}

# Set the API key for Stripe requests
Stripe.api_key = Rails.configuration.stripe[:secret_key]

# Optionally configure the Stripe API version (uncomment if needed)
# Stripe.api_version = '2022-08-01'
