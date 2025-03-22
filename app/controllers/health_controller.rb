# app/controllers/health_controller.rb
class HealthController < ApplicationController
  # No authentication required for health checks
  # (The application doesn't use before_action :authenticate_request)
  
  def index
    render json: { status: 'ok', timestamp: Time.now.iso8601 }
  end
  
  def sidekiq_stats
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
    
    render json: stats
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
