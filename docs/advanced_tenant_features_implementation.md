# Phase 7: Advanced Multi-Tenant Features

This document describes the implementation of advanced multi-tenant features in the Shimizu Order Suite, including tenant-specific feature flags, metrics and analytics, and disaster recovery planning.

## 1. Tenant-Specific Feature Flags

### Overview

Tenant-specific feature flags allow for:
- Gradual rollout of new features to specific tenants
- A/B testing across different tenant segments
- Tenant-specific customizations without code changes

### Implementation

#### Feature Flag Model

```ruby
# app/models/feature_flag.rb
class FeatureFlag < ApplicationRecord
  include TenantScoping
  
  validates :key, presence: true, uniqueness: { scope: :restaurant_id }
  validates :enabled, inclusion: { in: [true, false] }
  
  # Optional percentage rollout
  validates :percentage, numericality: { 
    greater_than_or_equal_to: 0, 
    less_than_or_equal_to: 100,
    allow_nil: true 
  }
end
```

#### Feature Flag Service

```ruby
# app/services/feature_flag_service.rb
class FeatureFlagService
  include TenantContext
  
  # Check if a feature is enabled for the current tenant
  def feature_enabled?(feature_key, entity_id = nil)
    # Super admin bypass
    return true if Current.user&.super_admin? && Rails.env.development?
    
    # Find the feature flag
    feature = FeatureFlag.find_by(key: feature_key)
    
    # Feature doesn't exist for this tenant
    return false unless feature
    
    # Feature is explicitly enabled/disabled
    return feature.enabled unless feature.percentage
    
    # Percentage rollout based on entity ID
    return false unless entity_id
    
    # Deterministic hashing for consistent percentage rollout
    hash = Digest::MD5.hexdigest("#{feature_key}:#{entity_id}").to_i(16) % 100
    hash < feature.percentage
  end
  
  # Enable a feature for the current tenant
  def enable_feature(feature_key, percentage = nil)
    feature = FeatureFlag.find_or_initialize_by(key: feature_key)
    feature.enabled = true
    feature.percentage = percentage
    feature.save!
  end
  
  # Disable a feature for the current tenant
  def disable_feature(feature_key)
    feature = FeatureFlag.find_or_initialize_by(key: feature_key)
    feature.enabled = false
    feature.percentage = nil
    feature.save!
  end
end
```

#### Usage in Controllers and Views

```ruby
# In controllers
def show
  @order = Order.find(params[:id])
  
  # Check if new order UI is enabled
  @new_ui_enabled = FeatureFlagService.new.feature_enabled?('new_order_ui', @order.id)
  
  render :show
end

# In views
<% if FeatureFlagService.new.feature_enabled?('advanced_analytics') %>
  <%= render 'advanced_analytics_dashboard' %>
<% else %>
  <%= render 'basic_analytics_dashboard' %>
<% end %>
```

### Admin Interface

The admin interface allows restaurant administrators to:
- View available features
- Enable/disable features
- Set percentage rollouts for gradual deployment

## 2. Tenant Metrics and Analytics

### Overview

Tenant metrics and analytics provide:
- Monitoring of tenant health and activity
- Usage statistics for billing and capacity planning
- Security monitoring for unusual access patterns

### Implementation

#### Tenant Event Model

```ruby
# app/models/tenant_event.rb
class TenantEvent < ApplicationRecord
  include TenantScoping
  
  validates :event_type, presence: true
  validates :event_data, presence: true
  
  # Store event data as JSON
  serialize :event_data, JSON
  
  # Event types
  TYPES = [
    'user_login',
    'order_created',
    'payment_processed',
    'api_request',
    'error',
    'security_alert'
  ]
  
  validates :event_type, inclusion: { in: TYPES }
end
```

#### Metrics Middleware

```ruby
# app/middleware/tenant_metrics_middleware.rb
class TenantMetricsMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = ActionDispatch::Request.new(env)
    start_time = Time.current
    
    # Process the request
    status, headers, response = @app.call(env)
    
    # Skip metrics for excluded paths
    return [status, headers, response] if excluded_path?(request.path)
    
    # Record metrics if tenant context is available
    if Current.restaurant_id.present?
      duration = Time.current - start_time
      
      # Record API request event
      TenantEvent.create!(
        restaurant_id: Current.restaurant_id,
        event_type: 'api_request',
        event_data: {
          path: request.path,
          method: request.method,
          duration_ms: (duration * 1000).to_i,
          status: status,
          user_id: Current.user&.id
        }
      )
      
      # Update Prometheus metrics
      TENANT_REQUEST_DURATION
        .with(tenant: Current.restaurant_id.to_s, path: request.path, method: request.method)
        .observe(duration)
      
      TENANT_REQUEST_COUNT
        .with(tenant: Current.restaurant_id.to_s, path: request.path, method: request.method, status: status.to_s)
        .increment
    end
    
    [status, headers, response]
  end
  
  private
  
  def excluded_path?(path)
    # Skip metrics for these paths
    ['/health', '/metrics', '/assets/'].any? { |prefix| path.start_with?(prefix) }
  end
end
```

#### Prometheus Metrics

```ruby
# config/initializers/tenant_metrics_monitoring.rb
require 'prometheus/client'

# Create a registry
prometheus = Prometheus::Client.registry

# Define metrics
TENANT_REQUEST_COUNT = prometheus.counter(
  :tenant_request_count,
  docstring: 'A counter of tenant HTTP requests',
  labels: [:tenant, :path, :method, :status]
)

TENANT_REQUEST_DURATION = prometheus.histogram(
  :tenant_request_duration_seconds,
  docstring: 'A histogram of tenant request durations',
  labels: [:tenant, :path, :method]
)

TENANT_ERROR_COUNT = prometheus.counter(
  :tenant_error_count,
  docstring: 'A counter of tenant errors',
  labels: [:tenant, :error_type]
)

TENANT_ORDER_COUNT = prometheus.counter(
  :tenant_order_count,
  docstring: 'A counter of tenant orders',
  labels: [:tenant]
)

TENANT_PAYMENT_AMOUNT = prometheus.counter(
  :tenant_payment_amount_cents,
  docstring: 'A counter of tenant payment amounts in cents',
  labels: [:tenant, :payment_method]
)
```

#### Tenant Metrics Service

```ruby
# app/services/tenant_metrics_service.rb
class TenantMetricsService
  include TenantContext
  
  # Get tenant usage statistics
  def tenant_usage_stats(start_date = 30.days.ago.to_date, end_date = Date.today)
    {
      orders: {
        count: Order.where(created_at: start_date..end_date).count,
        total_amount: Order.where(created_at: start_date..end_date).sum(:total_amount)
      },
      users: {
        active_count: TenantEvent.where(event_type: 'user_login', created_at: start_date..end_date)
                                .pluck(:event_data)
                                .map { |data| data['user_id'] }
                                .uniq
                                .count,
        total_count: User.where(restaurant_id: current_restaurant_id).count
      },
      api_requests: {
        count: TenantEvent.where(event_type: 'api_request', created_at: start_date..end_date).count,
        average_duration: TenantEvent.where(event_type: 'api_request', created_at: start_date..end_date)
                                    .pluck(:event_data)
                                    .map { |data| data['duration_ms'] }
                                    .sum.to_f / 
                          TenantEvent.where(event_type: 'api_request', created_at: start_date..end_date).count
      },
      errors: {
        count: TenantEvent.where(event_type: 'error', created_at: start_date..end_date).count
      }
    }
  end
  
  # Get tenant health metrics
  def tenant_health_metrics
    {
      error_rate: calculate_error_rate,
      response_time: calculate_average_response_time,
      uptime: calculate_uptime,
      resource_usage: {
        database_size: calculate_database_size,
        storage_usage: calculate_storage_usage
      }
    }
  end
  
  private
  
  def calculate_error_rate
    total_requests = TenantEvent.where(event_type: 'api_request', created_at: 24.hours.ago..Time.current).count
    error_requests = TenantEvent.where(event_type: 'api_request', created_at: 24.hours.ago..Time.current)
                              .pluck(:event_data)
                              .count { |data| data['status'].to_i >= 500 }
    
    total_requests.zero? ? 0 : (error_requests.to_f / total_requests) * 100
  end
  
  def calculate_average_response_time
    events = TenantEvent.where(event_type: 'api_request', created_at: 1.hour.ago..Time.current)
    
    return 0 if events.empty?
    
    events.pluck(:event_data).map { |data| data['duration_ms'] }.sum.to_f / events.count
  end
  
  # Additional calculation methods...
end
```

### Grafana Dashboard

A Grafana dashboard visualizes tenant metrics, including:
- Request rates and response times
- Error rates and types
- Order volumes and revenue
- User activity and growth

## 3. Disaster Recovery Planning

### Overview

Disaster recovery planning ensures:
- Data can be backed up and restored on a per-tenant basis
- Tenants can be migrated between environments
- The system can recover from failures with minimal data loss

### Implementation

#### Tenant Backup Service

```ruby
# app/services/tenant_backup_service.rb
class TenantBackupService
  class << self
    # Export all data for a specific tenant
    def export_tenant(restaurant, options = {})
      # Create a unique export ID
      export_id = "tenant_export_#{restaurant.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}"
      
      # Create a temporary directory for the export
      export_dir = Rails.root.join('tmp', 'exports', export_id)
      FileUtils.mkdir_p(export_dir)
      
      # Export each model's data
      tenant_models.each do |model|
        next unless model.column_names.include?('restaurant_id')
        
        table_name = model.table_name
        records = model.where(restaurant_id: restaurant.id).to_a
        
        # Skip if no records found and not explicitly included
        next if records.empty? && !options[:include_empty_tables]
        
        # Export the records to a JSON file
        file_path = export_dir.join("#{table_name}.json")
        File.write(file_path, records.to_json)
      end
      
      # Create a manifest file
      create_manifest(export_dir, restaurant, options)
      
      # Create a compressed archive
      archive_path = create_archive(export_dir, export_id)
      
      # Return the path to the archive
      archive_path
    end
    
    # Import tenant data from a backup
    def import_tenant(archive_path, options = {})
      # Extract the archive
      import_dir = extract_archive(archive_path)
      
      # Read the manifest
      manifest = read_manifest(import_dir)
      
      # Import the data
      ActiveRecord::Base.transaction do
        # Create or update the restaurant
        restaurant = import_restaurant(manifest, import_dir, options)
        
        # Import each table's data
        manifest['tables'].each do |table_name, table_info|
          import_table(table_name, table_info, import_dir, restaurant, options)
        end
        
        # Return the imported restaurant
        restaurant
      end
    end
    
    # Clone a tenant to a new restaurant
    def clone_tenant(source_restaurant, new_name, options = {})
      # Export the source tenant
      archive_path = export_tenant(source_restaurant, include_empty_tables: true)
      
      # Import with a new name
      import_tenant(archive_path, new_restaurant_name: new_name, options)
    end
    
    # Migrate a tenant to another environment
    def migrate_tenant(archive_path, target_env, options = {})
      # Validate the backup
      validate_backup(archive_path)
      
      # Determine the target server
      target_server = case target_env
                      when 'production'
                        ENV['PRODUCTION_SERVER']
                      when 'staging'
                        ENV['STAGING_SERVER']
                      else
                        raise ArgumentError, "Invalid target environment: #{target_env}"
                      end
      
      # Transfer the backup to the target server
      transfer_backup(archive_path, target_server, options)
    end
    
    # Validate a backup archive
    def validate_backup(archive_path)
      # Extract the archive
      validation_dir = extract_archive(archive_path)
      
      # Read the manifest
      manifest = read_manifest(validation_dir)
      
      # Validate the manifest structure
      validate_manifest_structure(manifest)
      
      # Validate each table file
      manifest['tables'].each do |table_name, table_info|
        validate_table_file(validation_dir, table_name, table_info)
      end
      
      # Return true if validation passes
      true
    end
    
    private
    
    # List of models that belong to a tenant
    def tenant_models
      [
        Restaurant,
        MenuItem,
        MenuCategory,
        Order,
        OrderItem,
        Customer,
        StaffMember,
        Reservation,
        Table,
        SpecialEvent,
        Promotion,
        LoyaltyProgram,
        LoyaltyReward,
        CustomerLoyalty,
        Feedback,
        Notification,
        PaymentMethod,
        TenantEvent,
        FeatureFlag
      ]
    end
    
    # Additional helper methods...
  end
end
```

#### Backup Controller

```ruby
# app/controllers/admin/tenant_backup_controller.rb
class Admin::TenantBackupController < ApplicationController
  before_action :authorize_super_admin, except: [:export_tenant, :backup_status]
  before_action :authorize_admin, only: [:export_tenant, :backup_status]
  
  # List all available backups
  def backups
    @backups = list_backup_files
    render json: { backups: @backups }
  end
  
  # Export a tenant's data
  def export_tenant
    restaurant = Restaurant.find(params[:id])
    
    # Start the export in a background job
    job = TenantBackupJob.perform_later('export', restaurant_id: restaurant.id)
    
    render json: {
      message: "Export started for #{restaurant.name}",
      job_id: job.job_id
    }
  end
  
  # Import a tenant from a backup
  def import_tenant
    # Validate the backup
    backup_file = find_backup_file(params[:backup_id])
    
    # Start the import in a background job
    job = TenantBackupJob.perform_later(
      'import',
      backup_id: params[:backup_id],
      target_restaurant_id: params[:target_restaurant_id],
      new_restaurant_name: params[:new_restaurant_name]
    )
    
    render json: {
      message: "Import started",
      job_id: job.job_id
    }
  end
  
  # Additional controller actions...
end
```

#### Scheduled Backups

```ruby
# lib/tasks/tenant_backup.rake
namespace :tenant do
  namespace :backup do
    desc "Backup all tenants"
    task :all => :environment do
      # Get all active restaurants
      restaurants = Restaurant.where(active: true)
      
      # Backup each restaurant
      restaurants.each do |restaurant|
        TenantBackupService.export_tenant(restaurant)
      end
    end
    
    desc "Clean up old backups, keeping only the specified number of recent backups per tenant"
    task :cleanup, [:keep_count] => :environment do |t, args|
      keep_count = (args[:keep_count] || 5).to_i
      
      # Group backups by restaurant
      backups_by_restaurant = group_backups_by_restaurant
      
      # Keep only the specified number of recent backups
      backups_by_restaurant.each do |restaurant_id, backups|
        sorted_backups = backups.sort_by { |b| b[:created_at] }.reverse
        backups_to_delete = sorted_backups[keep_count..-1] || []
        
        # Delete old backups
        backups_to_delete.each { |b| File.delete(b[:path]) }
      end
    end
    
    # Additional rake tasks...
  end
end
```

### Documentation

Comprehensive documentation covers:
- Backup and restore procedures
- Disaster recovery protocols
- Tenant migration processes
- Testing and validation procedures

## Best Practices

When implementing advanced multi-tenant features:

1. **Feature Flags**
   - Use a consistent naming convention for feature keys
   - Document all available features
   - Implement gradual rollout for major changes

2. **Metrics and Analytics**
   - Collect only necessary data to avoid performance impact
   - Set up alerts for abnormal patterns
   - Regularly review metrics for optimization opportunities

3. **Disaster Recovery**
   - Test backup and restore procedures regularly
   - Automate routine backups
   - Maintain multiple backup copies in different locations
   - Document recovery procedures clearly

## Conclusion

Advanced multi-tenant features enhance the platform's flexibility, observability, and resilience. By implementing tenant-specific feature flags, comprehensive metrics and analytics, and robust disaster recovery planning, we ensure that the Shimizu Order Suite can meet the diverse needs of our tenants while maintaining high availability and data integrity.
