# Schema Verification System

This document describes the schema verification system implemented to prevent and detect schema inconsistencies between the application's schema.rb file and the actual database structure.

## Overview

The schema verification system consists of several components:

1. **Startup Verification**: Checks schema integrity when the application starts
2. **Health Check Endpoint**: Provides an HTTP endpoint to verify schema integrity
3. **Verification Script**: A standalone script that can be run manually or as part of deployment
4. **Deployment Script**: Integrates schema verification into the deployment process

## Components

### 1. Startup Verification

The application checks schema integrity on startup via the `schema_verification.rb` initializer:

```ruby
# config/initializers/schema_verification.rb
if Rails.env.production?
  Rails.application.config.after_initialize do
    begin
      Rails.logger.info "Verifying database schema integrity..."
      
      # Orders table verification
      missing_columns = []
      expected_order_columns = ['id', 'restaurant_id', 'user_id', 'items', 'status', 'total', 
                         'promo_code', 'special_instructions', 'estimated_pickup_time', 
                         'created_at', 'updated_at', 'contact_name', 'contact_phone', 
                         'contact_email', 'payment_method', 'transaction_id', 
                         'payment_status', 'payment_amount', 'vip_code', 'vip_access_code_id']
      
      actual_columns = Order.column_names
      missing_from_order = expected_order_columns - actual_columns
      
      if missing_from_order.any?
        missing_columns << "Orders table missing: #{missing_from_order.join(', ')}"
      end
      
      # Add similar checks for other critical tables here
      
      if missing_columns.any?
        message = "SCHEMA INTEGRITY ERROR: #{missing_columns.join('; ')}"
        Rails.logger.error message
        
        # Optional: Send an alert via email or other notification system
        # AdminMailer.schema_error_alert(message).deliver_now if defined?(AdminMailer)
      else
        Rails.logger.info "Database schema integrity verified successfully"
      end
    rescue => e
      Rails.logger.error "Error during schema verification: #{e.message}"
    end
  end
end
```

### 2. Health Check Endpoint

The `/health/check` endpoint verifies schema integrity and can be used for monitoring:

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  # Skip authentication for health checks
  skip_before_action :authorize_request, if: -> { action_name == 'check' }
  
  def check
    inconsistencies = []
    
    # Check orders table
    expected_order_columns = ['id', 'restaurant_id', 'user_id', 'items', 'status', 'total', 
                       'promo_code', 'special_instructions', 'estimated_pickup_time', 
                       'created_at', 'updated_at', 'contact_name', 'contact_phone', 
                       'contact_email', 'payment_method', 'transaction_id', 
                       'payment_status', 'payment_amount', 'vip_code', 'vip_access_code_id']
    
    actual_columns = Order.column_names
    missing_from_order = expected_order_columns - actual_columns
    
    if missing_from_order.any?
      inconsistencies << "Orders table missing: #{missing_from_order.join(', ')}"
    end
    
    # Add checks for other critical tables as needed
    
    if inconsistencies.any?
      render json: { status: 'error', schema_issues: inconsistencies }, status: :service_unavailable
    else
      render json: { status: 'ok', message: 'Schema integrity verified' }
    end
  end
end
```

### 3. Verification Script

The `script/verify_schema.rb` script can be run manually to check for schema inconsistencies:

```ruby
#!/usr/bin/env ruby
# script/verify_schema.rb
require_relative '../config/environment'

puts "Checking schema consistency..."
puts "-----------------------------"

inconsistencies_found = false

ActiveRecord::Base.connection.tables.each do |table|
  # Skip internal Rails tables
  next if ['schema_migrations', 'ar_internal_metadata'].include?(table)
  
  # Get columns from schema.rb
  expected_columns = ActiveRecord::Base.connection.columns(table).map(&:name).sort
  
  # Get columns directly from database
  actual_columns = ActiveRecord::Base.connection.exec_query(
    "SELECT column_name FROM information_schema.columns WHERE table_name = '#{table}'"
  ).rows.flatten.sort
  
  # Find missing columns
  missing_columns = expected_columns - actual_columns
  extra_columns = actual_columns - expected_columns
  
  if missing_columns.any? || extra_columns.any?
    inconsistencies_found = true
    puts "\n[!] Table '#{table}' has inconsistencies:"
    
    if missing_columns.any?
      puts "   - Missing columns (in schema.rb but not in database): #{missing_columns.join(', ')}"
    end
    
    if extra_columns.any?
      puts "   - Extra columns (in database but not in schema.rb): #{extra_columns.join(', ')}"
    end
  end
end

unless inconsistencies_found
  puts "\n[✓] All tables consistent between schema.rb and database!"
end
```

### 4. Deployment Script

The `bin/deploy.sh` script integrates schema verification into the deployment process:

```bash
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
```

## Usage

### During Deployment

1. Deploy code to Render
2. SSH into the Render instance
3. Run the deployment script: `./bin/deploy.sh`
4. Restart the application from the Render dashboard

### Manual Verification

To manually check for schema inconsistencies:

```bash
RAILS_ENV=production rails runner script/verify_schema.rb
```

### Health Check Monitoring

Configure the `/health/check` endpoint as a health check in Render or other monitoring tools.

## Best Practices

For detailed best practices on writing migrations to prevent schema inconsistencies, see [Migration Best Practices](migration_best_practices.md).
