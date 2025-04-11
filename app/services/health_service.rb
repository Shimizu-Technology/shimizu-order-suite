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
