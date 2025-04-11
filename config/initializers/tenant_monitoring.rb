# config/initializers/tenant_monitoring.rb
# Minimal version for compatibility with prometheus-client 4.2.4

# Skip monitoring in development/test environments
unless Rails.env.production? || Rails.env.staging?
  # Create empty module to avoid undefined constant errors
  module TenantMonitoring
    def self.record_access(restaurant_id); end
    def self.record_cross_tenant_access(restaurant_id, user_id); end
    def self.record_rate_limit(restaurant_id); end
  end
  
  Rails.logger.info "Tenant monitoring disabled in #{Rails.env} environment"
  return
end

# Initialize monitoring client
require 'prometheus/client'

# Create a registry for our metrics
TENANT_METRICS = Prometheus::Client.registry

# Define metrics for tenant isolation monitoring with new API syntax
CROSS_TENANT_ACCESS_COUNTER = TENANT_METRICS.counter(
  name: :shimizu_cross_tenant_access_attempts_total,
  docstring: 'Total number of cross-tenant access attempts',
  labels: [:restaurant_id, :user_id]
)

TENANT_ACCESS_COUNTER = TENANT_METRICS.counter(
  name: :shimizu_tenant_access_total,
  docstring: 'Total number of tenant access operations',
  labels: [:restaurant_id]
)

RATE_LIMIT_EXCEEDED_COUNTER = TENANT_METRICS.counter(
  name: :shimizu_rate_limit_exceeded_total,
  docstring: 'Total number of rate limit exceeded events',
  labels: [:restaurant_id]
)

# Create a simple module for monitoring
module TenantMonitoring
  def self.record_access(restaurant_id)
    return unless restaurant_id
    TENANT_ACCESS_COUNTER.increment(restaurant_id: restaurant_id.to_s)
  end
  
  def self.record_cross_tenant_access(restaurant_id, user_id)
    return unless restaurant_id
    CROSS_TENANT_ACCESS_COUNTER.increment(
      restaurant_id: restaurant_id.to_s,
      user_id: user_id.to_s || 'unknown'
    )
  end
  
  def self.record_rate_limit(restaurant_id)
    return unless restaurant_id
    RATE_LIMIT_EXCEEDED_COUNTER.increment(restaurant_id: restaurant_id.to_s)
  end
end

# Log that monitoring is enabled
Rails.logger.info "Tenant isolation monitoring enabled with #{TENANT_METRICS.metrics.size} metrics"
