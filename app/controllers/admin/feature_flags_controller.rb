# app/controllers/admin/feature_flags_controller.rb
#
# The Admin::FeatureFlagsController provides an interface for managing
# feature flags in the application. It allows administrators to enable
# and disable features globally or for specific tenants.
#
class Admin::FeatureFlagsController < ApplicationController
  before_action :authorize_super_admin, except: [:index, :show]
  before_action :authorize_admin, only: [:index, :show]
  before_action :set_feature_flag, only: [:show, :update, :destroy]
  
  # GET /admin/feature_flags
  def index
    # For super admins, show all flags
    if current_user.super_admin?
      @global_flags = FeatureFlag.global.order(:name)
      @tenant_flags = FeatureFlag.tenant_specific.order(:name, :restaurant_id)
      
      render json: {
        global_flags: @global_flags,
        tenant_flags: @tenant_flags
      }
    else
      # For regular admins, show only flags for their restaurant
      @flags = FeatureFlag.where(restaurant_id: current_restaurant.id)
                         .or(FeatureFlag.global)
                         .order(:name)
      
      render json: { flags: @flags }
    end
  end
  
  # GET /admin/feature_flags/:id
  def show
    # Ensure tenant access
    authorize_tenant_access(@feature_flag.restaurant_id) if @feature_flag.restaurant_id.present?
    
    render json: @feature_flag
  end
  
  # POST /admin/feature_flags
  def create
    # Handle global flag creation
    if feature_flag_params[:global] && current_user.super_admin?
      @feature_flag = FeatureFlag.new(
        name: feature_flag_params[:name],
        description: feature_flag_params[:description],
        enabled: feature_flag_params[:enabled],
        global: true,
        configuration: feature_flag_params[:configuration]
      )
    else
      # Handle tenant-specific flag creation
      restaurant_id = feature_flag_params[:restaurant_id] || current_restaurant.id
      
      # Ensure tenant access
      authorize_tenant_access(restaurant_id)
      
      @feature_flag = FeatureFlag.new(
        name: feature_flag_params[:name],
        description: feature_flag_params[:description],
        enabled: feature_flag_params[:enabled],
        global: false,
        restaurant_id: restaurant_id,
        configuration: feature_flag_params[:configuration]
      )
    end
    
    if @feature_flag.save
      # Log the creation
      AuditLog.log_data_modification(
        current_user,
        'create',
        'FeatureFlag',
        @feature_flag.id,
        request.remote_ip,
        { feature_name: @feature_flag.name, enabled: @feature_flag.enabled }
      )
      
      render json: @feature_flag, status: :created
    else
      render json: { errors: @feature_flag.errors }, status: :unprocessable_entity
    end
  end
  
  # PATCH/PUT /admin/feature_flags/:id
  def update
    # Ensure tenant access
    authorize_tenant_access(@feature_flag.restaurant_id) if @feature_flag.restaurant_id.present?
    
    # Only super admins can update global flags
    if @feature_flag.global && !current_user.super_admin?
      return render json: { error: "Only super admins can update global feature flags" }, status: :forbidden
    end
    
    if @feature_flag.update(feature_flag_params.except(:global, :restaurant_id))
      # Log the update
      AuditLog.log_data_modification(
        current_user,
        'update',
        'FeatureFlag',
        @feature_flag.id,
        request.remote_ip,
        { feature_name: @feature_flag.name, enabled: @feature_flag.enabled }
      )
      
      render json: @feature_flag
    else
      render json: { errors: @feature_flag.errors }, status: :unprocessable_entity
    end
  end
  
  # DELETE /admin/feature_flags/:id
  def destroy
    # Ensure tenant access
    authorize_tenant_access(@feature_flag.restaurant_id) if @feature_flag.restaurant_id.present?
    
    # Only super admins can delete global flags
    if @feature_flag.global && !current_user.super_admin?
      return render json: { error: "Only super admins can delete global feature flags" }, status: :forbidden
    end
    
    # Log the deletion
    AuditLog.log_data_modification(
      current_user,
      'delete',
      'FeatureFlag',
      @feature_flag.id,
      request.remote_ip,
      { feature_name: @feature_flag.name }
    )
    
    @feature_flag.destroy
    head :no_content
  end
  
  # POST /admin/feature_flags/enable_for_tenant
  def enable_for_tenant
    restaurant_id = params[:restaurant_id] || current_restaurant.id
    
    # Ensure tenant access
    authorize_tenant_access(restaurant_id)
    
    restaurant = Restaurant.find(restaurant_id)
    feature_name = params[:feature_name]
    configuration = params[:configuration]
    
    @feature_flag = FeatureFlagService.enable_for_tenant(feature_name, restaurant, configuration)
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'update',
      'FeatureFlag',
      @feature_flag.id,
      request.remote_ip,
      { feature_name: feature_name, action: 'enable_for_tenant', restaurant_id: restaurant_id }
    )
    
    render json: @feature_flag
  end
  
  # POST /admin/feature_flags/disable_for_tenant
  def disable_for_tenant
    restaurant_id = params[:restaurant_id] || current_restaurant.id
    
    # Ensure tenant access
    authorize_tenant_access(restaurant_id)
    
    restaurant = Restaurant.find(restaurant_id)
    feature_name = params[:feature_name]
    
    @feature_flag = FeatureFlagService.disable_for_tenant(feature_name, restaurant)
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'update',
      'FeatureFlag',
      @feature_flag.id,
      request.remote_ip,
      { feature_name: feature_name, action: 'disable_for_tenant', restaurant_id: restaurant_id }
    )
    
    render json: @feature_flag
  end
  
  # POST /admin/feature_flags/enable_globally
  def enable_globally
    # Only super admins can enable features globally
    authorize_super_admin
    
    feature_name = params[:feature_name]
    configuration = params[:configuration]
    
    @feature_flag = FeatureFlagService.enable_globally(feature_name, configuration)
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'update',
      'FeatureFlag',
      @feature_flag.id,
      request.remote_ip,
      { feature_name: feature_name, action: 'enable_globally' }
    )
    
    render json: @feature_flag
  end
  
  # POST /admin/feature_flags/disable_globally
  def disable_globally
    # Only super admins can disable features globally
    authorize_super_admin
    
    feature_name = params[:feature_name]
    
    @feature_flag = FeatureFlagService.disable_globally(feature_name)
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'update',
      'FeatureFlag',
      @feature_flag.id,
      request.remote_ip,
      { feature_name: feature_name, action: 'disable_globally' }
    )
    
    render json: @feature_flag
  end
  
  private
  
  def set_feature_flag
    @feature_flag = FeatureFlag.find(params[:id])
  end
  
  def feature_flag_params
    params.require(:feature_flag).permit(:name, :description, :enabled, :global, :restaurant_id, configuration: {})
  end
  
  def authorize_admin
    unless current_user&.admin? || current_user&.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
  
  def authorize_super_admin
    unless current_user&.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
  
  def authorize_tenant_access(restaurant_id)
    # Super admins can access any tenant
    return true if current_user&.super_admin?
    
    # Regular users can only access their own tenant
    unless current_user&.restaurant_id == restaurant_id.to_i
      render json: { error: "You don't have permission to access this restaurant's data" }, status: :forbidden
      return false
    end
    
    true
  end
end
