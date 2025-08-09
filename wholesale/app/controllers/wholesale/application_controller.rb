module Wholesale
  class ApplicationController < ::ApplicationController
    # Inherit from main app's ApplicationController to get:
    # - TenantIsolation concern
    # - Pundit authorization
    # - JWT authentication
    # - API-only behavior
    
    # Wholesale-specific before actions - ensure auth runs BEFORE tenant isolation
    skip_before_action :set_current_tenant
    before_action :authorize_request, except: [:health, :api_info]
    before_action :set_current_tenant, except: [:health, :api_info]
    before_action :validate_fundraiser_access, if: :fundraiser_params_present?
    
    # Public endpoints
    def health
      render json: {
        status: 'ok',
        service: 'wholesale-api',
        timestamp: Time.current.iso8601,
        version: '1.0.0'
      }
    end
    
    def api_info
      render json: {
        service: 'Wholesale Fundraising API',
        version: '1.0.0',
        description: 'API for wholesale fundraising orders and cart management',
        endpoints: {
          fundraisers: '/wholesale/fundraisers',
          items: '/wholesale/items',
          cart: '/wholesale/cart',
          orders: '/wholesale/orders',
          payments: '/wholesale/payments'
        },
        documentation: 'See PRD for detailed API documentation'
      }
    end
    
    protected
    
    # Get the current user (inherited from main ApplicationController)
    def current_user
      @current_user
    end
    
    # Get the current restaurant/tenant (inherited from TenantIsolation)
    def current_restaurant
      @current_restaurant
    end
    
    # Helper method to render JSON responses consistently
    def render_success(data = nil, message = nil, status: :ok)
      response = { success: true }
      response[:message] = message if message.present?
      response[:data] = data if data.present?
      render json: response, status: status
    end
    
    def render_error(message, status: :unprocessable_entity, errors: nil)
      response = { 
        success: false, 
        message: message 
      }
      response[:errors] = errors if errors.present?
      render json: response, status: status
    end
    
    def render_not_found(message = "Resource not found")
      render_error(message, status: :not_found)
    end
    
    def render_unauthorized(message = "Unauthorized access")
      render_error(message, status: :unauthorized)
    end
    
    # Fundraiser context helpers
    def find_fundraiser_by_slug
      @fundraiser ||= Wholesale::Fundraiser
        .where(restaurant: current_restaurant)
        .active
        .current
        .find_by!(slug: params[:fundraiser_slug] || params[:slug])
    rescue ActiveRecord::RecordNotFound
      render_not_found("Fundraiser not found")
      nil
    end
    
    def find_fundraiser_by_id
      @fundraiser ||= Wholesale::Fundraiser.where(restaurant: current_restaurant).find(params[:fundraiser_id])
    rescue ActiveRecord::RecordNotFound
      render_not_found("Fundraiser not found")
      nil
    end
    
    # Validate that fundraiser is accessible (active and current)
    def validate_fundraiser_access
      return unless @fundraiser
      
      unless @fundraiser.active?
        render_error("This fundraiser is not currently active", status: :forbidden)
        return false
      end
      
      unless @fundraiser.current?
        render_error("This fundraiser is not currently accepting orders", status: :forbidden)
        return false
      end
      
      true
    end
    
    private
    
    def fundraiser_params_present?
      params[:fundraiser_slug].present? || params[:slug].present? || params[:fundraiser_id].present?
    end
    
    # Override authorize_request to allow some public endpoints
    def authorize_request
      # Skip auth for some public endpoints like fundraiser listing
      return if skip_authorization?
      
      super
    end
    
    def skip_authorization?
      # Define which actions don't require authentication
      # Only allow public access for non-admin controllers
      return false if params[:controller]&.include?('admin')
      
      public_actions = {
        'fundraisers' => ['index', 'show'],
        'items' => ['index', 'show']
      }
      
      controller_name = params[:controller]&.split('/')&.last
      action_name = params[:action]
      
      public_actions[controller_name]&.include?(action_name)
    end
    
    # Ensure we have tenant context for all wholesale operations
    def ensure_tenant_context
      unless current_restaurant
        render_error("Restaurant context required", status: :bad_request)
        return false
      end
      
      true
    end

    # Render helper methods for consistent API responses
    def render_success(data = {}, status = :ok)
      response_data = {
        success: true,
        data: data.except(:message),
        message: data[:message] || 'Request completed successfully'
      }
      render json: response_data, status: status
    end

    def render_error(message, status: :unprocessable_entity, errors: nil)
      response_data = {
        success: false,
        message: message,
        errors: errors
      }.compact
      render json: response_data, status: status
    end

    def render_not_found(message = 'Resource not found')
      render_error(message, status: :not_found)
    end

    def render_bad_request(message = 'Bad request', errors: nil)
      render_error(message, status: :bad_request, errors: errors)
    end

    def render_unauthorized(message = 'Unauthorized access')
      render_error(message, status: :unauthorized)
    end

    def render_forbidden(message = 'Access forbidden')
      render_error(message, status: :forbidden)
    end
  end
end
