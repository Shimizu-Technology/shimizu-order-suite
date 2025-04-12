# app/services/restaurant_management_service.rb
class RestaurantManagementService < TenantScopedService
  # Indicate that this service supports global operations
  def self.global_service?
    true
  end
  
  # Add attr_accessor for current_user to make it accessible
  attr_accessor :current_user
  # Override initialize to make restaurant parameter optional for global admin operations
  # @param restaurant [Restaurant] Optional restaurant context
  # @param current_user [User] Optional current user
  def initialize(restaurant = nil, current_user = nil)
    # For global admin operations, restaurant can be nil
    if restaurant.nil?
      # Just set the instance variable directly without calling super
      @restaurant = nil
    else
      # Call the parent class's initialize method with the restaurant
      super(restaurant)
    end
    
    # Set the current user if provided
    @current_user = current_user
  end

  # Get all restaurants (only accessible by super_admin)
  def list_restaurants
    # For super_admin, return all restaurants
    # For regular admin, return only their restaurant
    if current_user&.super_admin?
      Restaurant.all.order(:name)
    else
      # Regular admins should only see their own restaurant
      [current_restaurant].compact
    end
  end

  # Get allowed origins for a restaurant
  def get_allowed_origins
    # Return the allowed origins for the current restaurant
    { allowed_origins: current_restaurant.allowed_origins || [] }
  end

  # Update allowed origins for a restaurant
  def update_allowed_origins(allowed_origins)
    # Validate the input
    unless allowed_origins.is_a?(Array)
      return { success: false, error: "allowed_origins must be an array", status: :unprocessable_entity }
    end

    # Update the allowed origins
    current_restaurant.allowed_origins = allowed_origins
    
    if current_restaurant.save
      { success: true, allowed_origins: current_restaurant.allowed_origins }
    else
      { success: false, errors: current_restaurant.errors.full_messages, status: :unprocessable_entity }
    end
  end
  
  private
  
  # Get the current user from the service context
  # This is now redundant since we have attr_accessor :current_user
  # but keeping it for backward compatibility
  def current_user
    @current_user
  end
end
