# app/controllers/health_controller.rb
class HealthController < ApplicationController
  include TenantIsolation
  
  # Override global_access_permitted to allow access without tenant context
  # Health checks are truly global endpoints that don't require tenant context
  def global_access_permitted?
    true
  end
  
  def index
    result = health_service.health_status
    
    if result[:success]
      render json: { status: result[:status], timestamp: result[:timestamp] }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  def sidekiq_stats
    result = health_service.sidekiq_stats
    
    if result[:success]
      render json: result[:stats]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end

  # Lightweight readiness contract for public frontends. Unlike the generic
  # process health check, this verifies that the requested tenant can be read
  # from the database without returning any restaurant configuration.
  def frontend
    result = health_service.frontend_status(params[:restaurant_id])

    if result[:success]
      render json: {
        status: result[:status],
        restaurant_id: result[:restaurant_id]
      }
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  private
  
  def health_service
    @health_service ||= HealthService.new(current_restaurant, analytics)
  end
end
