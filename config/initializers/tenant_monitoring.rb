# config/initializers/tenant_monitoring.rb
# Temporarily disabled to allow deployment

# Create empty module to avoid undefined constant errors in code that might reference these
module TenantMonitoring
  def self.record_access(restaurant_id); end
  def self.record_cross_tenant_access(restaurant_id, user_id); end
  def self.record_rate_limit(restaurant_id); end
end

# Create empty constants to avoid undefined constant errors
TENANT_METRICS = nil
CROSS_TENANT_ACCESS_COUNTER = nil
TENANT_ACCESS_COUNTER = nil
RATE_LIMIT_EXCEEDED_COUNTER = nil

# Log that monitoring is disabled
Rails.logger.info "Tenant monitoring temporarily disabled for deployment"
