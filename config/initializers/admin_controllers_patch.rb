# config/initializers/admin_controllers_patch.rb
#
# This initializer patches admin controllers to properly handle tenant access
# for authenticated users accessing their own restaurant's data.

Rails.application.config.after_initialize do
  # Only apply the patch if we're in production
  if Rails.env.production?
    Rails.logger.info "Applying admin controllers patch for authenticated access..."
    
    # Patch OrdersController
    if defined?(OrdersController)
      OrdersController.class_eval do
        # Override validate_tenant_access to allow authenticated users to access their restaurant
        def validate_tenant_access(restaurant)
          # Allow authenticated users to access their own restaurant
          if current_user && current_user.restaurant_id == restaurant&.id
            Rails.logger.debug { "Allowing authenticated user #{current_user.id} to access restaurant #{restaurant.id}" }
            return true
          end
          
          # Fall back to the standard validation
          super
        end
      end
      Rails.logger.info "✅ Patched OrdersController"
    end
    
    # Patch StaffMembersController
    if defined?(StaffMembersController)
      StaffMembersController.class_eval do
        # Override validate_tenant_access to allow authenticated users to access their restaurant
        def validate_tenant_access(restaurant)
          # Allow authenticated users to access their own restaurant
          if current_user && current_user.restaurant_id == restaurant&.id
            Rails.logger.debug { "Allowing authenticated user #{current_user.id} to access restaurant #{restaurant.id}" }
            return true
          end
          
          # Fall back to the standard validation
          super
        end
      end
      Rails.logger.info "✅ Patched StaffMembersController"
    end
    
    # Patch UsersController
    if defined?(UsersController)
      UsersController.class_eval do
        # Override validate_tenant_access to allow authenticated users to access their restaurant
        def validate_tenant_access(restaurant)
          # Allow authenticated users to access their own restaurant
          if current_user && current_user.restaurant_id == restaurant&.id
            Rails.logger.debug { "Allowing authenticated user #{current_user.id} to access restaurant #{restaurant.id}" }
            return true
          end
          
          # Fall back to the standard validation
          super
        end
      end
      Rails.logger.info "✅ Patched UsersController"
    end
    
    # Patch Admin::AnalyticsController
    if defined?(Admin::AnalyticsController)
      Admin::AnalyticsController.class_eval do
        # Override validate_tenant_access to allow authenticated users to access their restaurant
        def validate_tenant_access(restaurant)
          # Allow authenticated users to access their own restaurant
          if current_user && current_user.restaurant_id == restaurant&.id
            Rails.logger.debug { "Allowing authenticated user #{current_user.id} to access restaurant #{restaurant.id}" }
            return true
          end
          
          # Fall back to the standard validation
          super
        end
      end
      Rails.logger.info "✅ Patched Admin::AnalyticsController"
    end
    
    Rails.logger.info "Admin controllers patch completed."
  end
end
