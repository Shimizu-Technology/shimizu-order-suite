# app/services/health_service.rb
class HealthService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant = nil, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Get basic health status
  def health_status
    begin
      { 
        success: true, 
        status: 'ok', 
        timestamp: Time.now.iso8601 
      }
    rescue => e
      { success: false, errors: ["Failed to get health status: #{e.message}"], status: :internal_server_error }
    end
  end

  # Verify that a public frontend's tenant is available without exposing any
  # tenant data. This intentionally checks the database as well as the Rails
  # process so frontends can fall back cleanly during a database outage.
  def frontend_status(restaurant_id)
    return {
      success: false,
      errors: [ "restaurant_id is required" ],
      status: :bad_request
    } if restaurant_id.blank?

    normalized_id = Integer(restaurant_id, exception: false)
    return {
      success: false,
      errors: [ "restaurant_id must be a positive integer" ],
      status: :bad_request
    } unless normalized_id&.positive?

    restaurant = Restaurant.unscoped.select(:id).find_by(id: normalized_id)
    return {
      success: false,
      errors: [ "Restaurant not found" ],
      status: :not_found
    } unless restaurant

    {
      success: true,
      status: "available",
      restaurant_id: restaurant.id
    }
  rescue StandardError => e
    Rails.logger.error("Frontend readiness check failed: #{e.class}: #{e.message}")
    {
      success: false,
      errors: [ "Service readiness could not be verified" ],
      status: :service_unavailable
    }
  end
  
  # Get Sidekiq stats
  def sidekiq_stats
    begin
      stats = {
        processed: Sidekiq::Stats.new.processed,
        failed: Sidekiq::Stats.new.failed,
        queues: Sidekiq::Stats.new.queues,
        scheduled_size: Sidekiq::Stats.new.scheduled_size,
        retry_size: Sidekiq::Stats.new.retry_size,
        workers: Sidekiq::Workers.new.size,
        process_count: Sidekiq::ProcessSet.new.size,
        redis_memory_usage: redis_memory_usage
      }
      
      { success: true, stats: stats }
    rescue => e
      { success: false, errors: ["Failed to get Sidekiq stats: #{e.message}"], status: :internal_server_error }
    end
  end
  
  private
  
  def redis_memory_usage
    begin
      Sidekiq.redis { |conn| conn.info('memory')['used_memory_human'] }
    rescue => e
      "Error fetching Redis memory: #{e.message}"
    end
  end
end
