module Admin
  class SystemController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_admin, except: [:test_pushover, :validate_pushover_key, :test_sms, :generate_web_push_keys]
    before_action :ensure_tenant_context, only: [:generate_web_push_keys]
    
    def test_sms
      # Use the SystemService to test SMS functionality
      result = system_service.test_sms(params)
      
      if result[:success]
        render json: { status: "success", message: result[:message] }
      else
        render json: { status: "error", message: result[:message] }, status: result[:status] || :internal_server_error
      end
    end
    
    def test_pushover
      # Use the SystemService to test Pushover notification
      result = system_service.test_pushover(params)
      
      if result[:success]
        render json: { status: "success", message: result[:message] }
      else
        render json: { status: "error", message: result[:message] }, status: result[:status] || :internal_server_error
      end
    end
    
    def validate_pushover_key
      # Use the SystemService to validate Pushover key
      result = system_service.validate_pushover_key(params)
      
      if result[:success]
        render json: { status: "success", message: result[:message], valid: result[:valid] }
      else
        render json: { status: "error", message: result[:message], valid: result[:valid] }, status: result[:status] || :bad_request
      end
    end
    
    def generate_web_push_keys
      # Use the SystemService to generate web push keys with tenant isolation
      # Pass the current_user as a parameter instead of setting it on the service
      result = system_service.generate_web_push_keys(params[:restaurant_id], current_user)
      
      if result[:success]
        render json: { 
          status: "success", 
          message: result[:message],
          public_key: result[:public_key],
          private_key: result[:private_key]
        }
      else
        render json: { 
          status: "error", 
          message: result[:message] 
        }, status: result[:status] || :internal_server_error
      end
    end
    
    private
    
    def authorize_admin
      unless current_user&.role.in?(%w[admin super_admin])
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
    
    def system_service
      @system_service ||= SystemService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end
    
    # Override global_access_permitted? from TenantIsolation concern
    # These endpoints are truly global and don't require tenant context
    def global_access_permitted?
      ["test_pushover", "validate_pushover_key", "test_sms"].include?(action_name)
    end
  end
end
