#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

echo "Starting deployment process..."

# 1. Run migrations
echo "Running database migrations..."
RAILS_ENV=production bundle exec rails db:migrate

# 2. Verify schema integrity
echo "Verifying schema integrity..."
RAILS_ENV=production bundle exec rails runner script/verify_schema.rb

# 3. Restart the application (Render-specific)
echo "Deployment completed successfully!"
echo "Please restart your Render service manually from the dashboard."
