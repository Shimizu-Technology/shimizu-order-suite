# app/models/audit_log.rb
#
# The AuditLog model is used to track important actions in the system,
# particularly those related to tenant access and data modifications.
# It provides a comprehensive audit trail for security and compliance purposes.
#
class AuditLog < ApplicationRecord
  include TenantScoped
  
  # Associations
  belongs_to :user, optional: true
  
  # Validations
  validates :action, presence: true
  
  # Scopes
  scope :tenant_access_logs, -> { where(action: 'tenant_access') }
  scope :data_modification_logs, -> { where(action: %w[create update delete]) }
  scope :suspicious_activity, -> { where(action: 'suspicious_activity') }
  
  # Class methods for common audit logging scenarios
  
  # Log tenant access
  # @param user [User] The user accessing the tenant
  # @param restaurant [Restaurant] The tenant being accessed
  # @param ip_address [String] The IP address of the request
  # @param details [Hash] Additional details about the access
  # @return [AuditLog] The created audit log
  def self.log_tenant_access(user, restaurant, ip_address, details = {})
    create(
      user_id: user&.id,
      restaurant_id: restaurant&.id,
      action: 'tenant_access',
      resource_type: 'Restaurant',
      resource_id: restaurant&.id,
      ip_address: ip_address,
      details: details
    )
  end
  
  # Log cross-tenant access attempt
  # @param user [User] The user attempting cross-tenant access
  # @param target_restaurant_id [Integer] The ID of the tenant being accessed
  # @param ip_address [String] The IP address of the request
  # @param details [Hash] Additional details about the access attempt
  # @return [AuditLog] The created audit log
  def self.log_cross_tenant_access(user, target_restaurant_id, ip_address, details = {})
    create(
      user_id: user&.id,
      restaurant_id: user&.restaurant_id,
      action: 'suspicious_activity',
      resource_type: 'Restaurant',
      resource_id: target_restaurant_id,
      ip_address: ip_address,
      details: details.merge({
        attempt_type: 'cross_tenant_access',
        user_restaurant_id: user&.restaurant_id,
        target_restaurant_id: target_restaurant_id
      })
    )
  end
  
  # Log data modification
  # @param user [User] The user modifying the data
  # @param action [String] The action being performed (create, update, delete)
  # @param resource_type [String] The type of resource being modified
  # @param resource_id [Integer] The ID of the resource being modified
  # @param ip_address [String] The IP address of the request
  # @param details [Hash] Additional details about the modification
  # @return [AuditLog] The created audit log
  def self.log_data_modification(user, action, resource_type, resource_id, ip_address, details = {})
    create(
      user_id: user&.id,
      restaurant_id: user&.restaurant_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      ip_address: ip_address,
      details: details
    )
  end
end
