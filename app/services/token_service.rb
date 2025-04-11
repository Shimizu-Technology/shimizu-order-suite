# app/services/token_service.rb
#
# The TokenService class provides methods for JWT token management,
# including generation, verification, and revocation.
#
class TokenService
  # Initialize Redis client for token revocation storage
  REDIS_CLIENT = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
  # Generate a JWT token for a user
  # @param user [User] The user to generate a token for
  # @param restaurant_id [Integer] Optional override for restaurant_id (for tenant switching)
  # @param expiration [Time] Token expiration time (defaults to 24 hours)
  # @return [String] JWT token
  def self.generate_token(user, restaurant_id = nil, expiration = 24.hours.from_now)
    # Use provided restaurant_id or fall back to user's restaurant_id
    tenant_id = restaurant_id || user.restaurant_id
    
    # Create token payload
    payload = {
      user_id: user.id,
      restaurant_id: tenant_id,
      role: user.role,
      tenant_permissions: user_permissions(user, tenant_id),
      jti: SecureRandom.uuid, # JWT ID for revocation
      iat: Time.current.to_i, # Issued at time
      exp: expiration.to_i
    }
    
    # Encode the token
    JWT.encode(payload, Rails.application.secret_key_base)
  end
  
  # Verify a JWT token and extract the payload
  # @param token [String] JWT token to verify
  # @return [Hash] Decoded token payload
  # @raise [JWT::DecodeError] If token is invalid
  # @raise [TokenRevokedError] If token has been revoked
  def self.verify_token(token)
    # Decode the token
    decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
    
    # Check if token has been revoked
    if token_revoked?(decoded["jti"])
      raise TokenRevokedError, "Token has been revoked"
    end
    
    # Return the decoded payload
    decoded
  end
  
  # Revoke a specific token
  # @param token [String] JWT token to revoke
  # @return [Boolean] Whether the token was successfully revoked
  def self.revoke_token(token)
    begin
      # Decode the token without verification to get the jti
      decoded = JWT.decode(token, nil, false)[0]
      jti = decoded["jti"]
      exp = decoded["exp"]
      
      # If no JTI, we can't revoke
      return false unless jti
      
      # Calculate TTL (time until token expires)
      ttl = [exp - Time.current.to_i, 0].max
      
      # Add to revoked tokens with expiration
      REDIS_CLIENT.setex("revoked_token:#{jti}", ttl, "1")
      true
    rescue => e
      Rails.logger.error("Failed to revoke token: #{e.message}")
      false
    end
  end
  
  # Revoke all tokens for a user
  # @param user_id [Integer] User ID to revoke tokens for
  # @return [Boolean] Whether the operation was successful
  def self.revoke_all_user_tokens(user_id)
    begin
      # Generate a unique revocation key for this user
      revocation_timestamp = Time.current.to_i
      REDIS_CLIENT.set("user_tokens_revoked_at:#{user_id}", revocation_timestamp)
      true
    rescue => e
      Rails.logger.error("Failed to revoke all user tokens: #{e.message}")
      false
    end
  end
  
  # Check if a token has been revoked
  # @param jti [String] JWT ID to check
  # @return [Boolean] Whether the token has been revoked
  def self.token_revoked?(jti)
    REDIS_CLIENT.exists?("revoked_token:#{jti}")
  end
  
  # Get user permissions for a specific tenant
  # @param user [User] The user to get permissions for
  # @param tenant_id [Integer] The tenant ID to get permissions for
  # @return [Hash] User permissions for the tenant
  def self.user_permissions(user, tenant_id)
    # Default permissions based on role
    permissions = case user.role
    when "super_admin"
      { can_access_all_tenants: true, can_manage_users: true, can_manage_settings: true }
    when "admin"
      { can_manage_users: true, can_manage_settings: true }
    when "staff"
      { can_view_orders: true, can_manage_orders: true }
    else
      { can_view_orders: true }
    end
    
    # Add tenant-specific permissions
    permissions[:tenant_id] = tenant_id
    
    # Return the permissions hash
    permissions
  end
  
  # Error class for revoked tokens
  class TokenRevokedError < StandardError; end
end
