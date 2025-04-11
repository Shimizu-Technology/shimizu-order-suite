# app/controllers/admin/tenant_metrics_controller.rb
#
# The Admin::TenantMetricsController provides an interface for administrators
# to view and analyze tenant-specific metrics and analytics data.
#
class Admin::TenantMetricsController < ApplicationController
  before_action :authorize_request
  before_action :require_admin!
  before_action :authorize_super_admin, only: [:all_tenants, :tenant_comparison]
  before_action :set_restaurant, only: [:show, :usage_stats, :health_metrics, :events]
  
  # GET /admin/tenant_metrics
  # For regular admins, shows metrics for their restaurant
  # For super admins, shows an overview of all restaurants
  def index
    if current_user.super_admin?
      # Get summary metrics for all restaurants
      @tenant_summaries = Restaurant.all.map do |restaurant|
        {
          id: restaurant.id,
          name: restaurant.name,
          metrics: {
            orders_count: Order.where(restaurant_id: restaurant.id).count,
            users_count: User.where(restaurant_id: restaurant.id).count,
            health: TenantMetricsService.tenant_health_metrics(restaurant)[:status]
          }
        }
      end
      
      # Get list of tenants with issues
      @tenants_with_issues = TenantMetricsService.tenants_with_issues
      
      render json: {
        tenant_summaries: @tenant_summaries,
        tenants_with_issues: @tenants_with_issues
      }
    else
      # Regular admin sees their own restaurant's metrics
      redirect_to action: :show, id: current_restaurant.id
    end
  end
  
  # GET /admin/tenant_metrics/:id
  # Shows detailed metrics for a specific restaurant
  def show
    # Get comprehensive metrics for the restaurant
    @metrics = {
      usage_stats: TenantMetricsService.tenant_usage_stats(@restaurant),
      health_metrics: TenantMetricsService.tenant_health_metrics(@restaurant),
      recent_events: TenantEvent.where(restaurant_id: @restaurant.id).recent
    }
    
    render json: @metrics
  end
  
  # GET /admin/tenant_metrics/:id/usage_stats
  # Shows detailed usage statistics for a specific restaurant
  def usage_stats
    start_date = params[:start_date] ? Date.parse(params[:start_date]) : 30.days.ago.to_date
    end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.today
    
    @stats = TenantMetricsService.tenant_usage_stats(@restaurant, start_date, end_date)
    
    render json: @stats
  end
  
  # GET /admin/tenant_metrics/:id/health_metrics
  # Shows health metrics for a specific restaurant
  def health_metrics
    @health = TenantMetricsService.tenant_health_metrics(@restaurant)
    
    render json: @health
  end
  
  # GET /admin/tenant_metrics/:id/events
  # Shows recent events for a specific restaurant
  def events
    @events = TenantEvent.where(restaurant_id: @restaurant.id)
    
    # Apply filters if provided
    @events = @events.by_type(params[:event_type]) if params[:event_type].present?
    
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date]).beginning_of_day
      end_date = Date.parse(params[:end_date]).end_of_day
      @events = @events.in_timeframe(start_date, end_date)
    end
    
    # Paginate results
    @events = @events.order(created_at: :desc).page(params[:page] || 1).per(params[:per_page] || 25)
    
    render json: {
      events: @events,
      meta: {
        total_count: @events.total_count,
        total_pages: @events.total_pages,
        current_page: @events.current_page
      }
    }
  end
  
  # GET /admin/tenant_metrics/all_tenants
  # Super admin only - shows metrics for all tenants
  def all_tenants
    @all_metrics = Restaurant.all.map do |restaurant|
      {
        id: restaurant.id,
        name: restaurant.name,
        usage_stats: TenantMetricsService.tenant_usage_stats(restaurant),
        health_metrics: TenantMetricsService.tenant_health_metrics(restaurant)
      }
    end
    
    render json: @all_metrics
  end
  
  # GET /admin/tenant_metrics/tenant_comparison
  # Super admin only - compares metrics across tenants
  def tenant_comparison
    # Get IDs of restaurants to compare
    restaurant_ids = params[:restaurant_ids]
    
    if restaurant_ids.blank?
      return render json: { error: "Please provide restaurant_ids to compare" }, status: :bad_request
    end
    
    # Get restaurants
    @restaurants = Restaurant.where(id: restaurant_ids)
    
    if @restaurants.count != restaurant_ids.count
      return render json: { error: "One or more restaurant IDs are invalid" }, status: :bad_request
    end
    
    # Get metrics for each restaurant
    @comparison = @restaurants.map do |restaurant|
      {
        id: restaurant.id,
        name: restaurant.name,
        metrics: TenantMetricsService.tenant_usage_stats(restaurant)
      }
    end
    
    render json: @comparison
  end
  
  private
  
  def set_restaurant
    @restaurant = if current_user.super_admin?
                    Restaurant.find(params[:id])
                  else
                    current_restaurant
                  end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Restaurant not found" }, status: :not_found
  end
  
  def authorize_super_admin
    unless current_user.super_admin?
      render json: { error: "You don't have permission to access this resource" }, status: :forbidden
    end
  end
  
  def require_admin!
    unless current_user&.admin? || current_user&.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
end
