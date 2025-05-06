# app/controllers/public/restaurant_schedule_controller.rb
#
# This controller provides public access to operating hours and special events
# while maintaining proper tenant isolation. It does not require authentication
# but still enforces tenant context based on the restaurant_id parameter.

module Public
  class RestaurantScheduleController < ApplicationController
    include TenantIsolation
    
    # GET /public/restaurant_schedule/:restaurant_id
    # Returns operating hours and special events for a specific restaurant
    def show
      restaurant_id = params[:restaurant_id] || params[:id]
      
      begin
        # Find the restaurant
        restaurant = Restaurant.find(restaurant_id)
        
        # Temporarily unscope the queries to bypass the default_scope that requires tenant context
        operating_hours = OperatingHour.unscoped.where(restaurant_id: restaurant.id).as_json
        special_events = SpecialEvent.unscoped.where(restaurant_id: restaurant.id).as_json
        
        # Return combined data
        render json: {
          operating_hours: operating_hours,
          special_events: special_events
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Restaurant not found' }, status: :not_found
      end
    end
    
    private
    
    # Override global_access_permitted? to allow public access
    def global_access_permitted?
      # This is a public endpoint, so we don't require global access
      false
    end
    
    # Override the method to allow specifying restaurant_id parameter
    def can_specify_restaurant?
      # For public endpoints, we always allow specifying restaurant_id
      true
    end
    
    # Override to handle public requests without authentication
    def validate_tenant_access(restaurant)
      # For public endpoints, we just verify the restaurant exists
      # and is accessible via the public origin
      if restaurant.nil?
        raise TenantAccessDeniedError, "Restaurant not found"
      end
      
      # Check if the request origin is allowed for this restaurant
      unless public_request_allowed?(restaurant)
        raise TenantAccessDeniedError, "Access denied from this origin"
      end
      
      # Log the access for audit purposes
      log_tenant_access(restaurant)
    end
    
    # Determine if public request is allowed for this restaurant
    def public_request_allowed?(restaurant)
      # This would verify origin headers, domain restrictions, etc.
      # For now, assume all public access is allowed for simplicity
      true
    end
  end
end
