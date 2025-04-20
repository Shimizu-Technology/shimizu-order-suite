# config/initializers/tenant_isolation_patch.rb
#
# This initializer patches the TenantIsolation concern to allow public access to endpoints
# that should be accessible without authentication.
#
# This is necessary for the frontend to work correctly with the backend.

Rails.application.config.after_initialize do
  # Only apply the patch if we're in production
  if Rails.env.production?
    Rails.logger.info "Applying TenantIsolation patch for public endpoints..."
    
    # Create a patch module for TenantIsolation
    module TenantIsolationPatch
      # Override the validate_tenant_access method to allow public access to endpoints
      def validate_tenant_access(restaurant)
        # Check if this is a public endpoint request (no authentication)
        is_public_request = !current_user.present?
        
        # For public requests to public endpoints, allow access
        if is_public_request && request.headers['Origin'].present?
          origin = request.headers['Origin']
          Rails.logger.debug { "Checking origin: #{origin} for restaurant: #{restaurant&.id}" }
          
          # Check if this origin is allowed for any restaurant
          if Restaurant.where("allowed_origins @> ARRAY[?]::varchar[]", [origin]).exists?
            Rails.logger.debug { "Origin #{origin} is allowed for some restaurant" }
            return true
          end
        end
        
        # Allow access to global endpoints for super_admins
        return true if restaurant.nil? && global_access_permitted? && current_user&.role == "super_admin"
        
        # In development/test environments, be more permissive
        if Rails.env.development? || Rails.env.test?
          # Still log the access for debugging purposes
          log_tenant_access(restaurant) unless controller_name == "sessions" || controller_name == "passwords"
          return true
        end
        
        # Log tenant access for auditing purposes (if not an authentication endpoint)
        unless controller_name == "sessions" || controller_name == "passwords"
          log_tenant_access(restaurant)
        end
        
        # Allow super_admins to access any restaurant
        return true if current_user&.role == "super_admin"
        
        # Allow users to access their own restaurant
        return true if current_user&.restaurant_id == restaurant&.id
        
        # Special case for authentication endpoints
        return true if controller_name == "sessions" || controller_name == "passwords"
        
        # Special case for public endpoints - this is the key addition
        # If this is a public endpoint (like restaurant show) and the restaurant exists, allow access
        if global_access_permitted? && restaurant.present?
          Rails.logger.debug { "Allowing access to global endpoint: #{controller_name}##{action_name} for restaurant: #{restaurant.id}" }
          return true
        end
        
        # If we get here, the user is trying to access a restaurant they don't have permission for
        # Log cross-tenant access attempt for security monitoring
        log_cross_tenant_access(restaurant&.id)
        
        raise TenantIsolation::TenantAccessDeniedError, "You don't have permission to access this restaurant's data"
      end
    end
    
    # Apply the patch to the TenantIsolation module
    if defined?(TenantIsolation)
      TenantIsolation.prepend(TenantIsolationPatch)
      Rails.logger.info "✅ Applied patch to TenantIsolation module"
    else
      Rails.logger.error "❌ Could not find TenantIsolation module"
    end
    
    # Patch controllers to allow public access to certain endpoints
    
    # RestaurantsController
    if defined?(RestaurantsController)
      RestaurantsController.class_eval do
        # Override global_access_permitted? to allow public access to show action
        def global_access_permitted?
          # Allow public access to show, toggle_vip_mode, and set_current_event
          action_name.in?(["show", "toggle_vip_mode", "set_current_event"])
        end
      end
      Rails.logger.info "✅ Patched RestaurantsController"
    end
    
    # Admin::SiteSettingsController
    if defined?(Admin::SiteSettingsController)
      Admin::SiteSettingsController.class_eval do
        # Allow public access to show action
        def global_access_permitted?
          action_name == "show"
        end
      end
      Rails.logger.info "✅ Patched Admin::SiteSettingsController"
    end
    
    # MenuItemsController
    if defined?(MenuItemsController)
      MenuItemsController.class_eval do
        # Allow public access to index and show actions
        def global_access_permitted?
          action_name.in?(["index", "show"])
        end
      end
      Rails.logger.info "✅ Patched MenuItemsController"
    end
    
    # MerchandiseCollectionsController
    if defined?(MerchandiseCollectionsController)
      MerchandiseCollectionsController.class_eval do
        # Allow public access to index and show actions
        def global_access_permitted?
          action_name.in?(["index", "show"])
        end
      end
      Rails.logger.info "✅ Patched MerchandiseCollectionsController"
    end
    
    Rails.logger.info "Tenant isolation patch completed."
  end
end
