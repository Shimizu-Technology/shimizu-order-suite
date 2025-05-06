# app/controllers/locations_controller.rb
class LocationsController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request, except: [:index, :show]
  before_action :ensure_tenant_context
  before_action :set_location, only: [:show, :update, :destroy, :set_default]
  before_action :authorize_admin, except: [:index, :show]
  
  # GET /locations
  def index
    # Determine if we should include inactive locations
    include_inactive = params[:is_active] != 'true' && params[:active] != 'true'
    
    # Log for debugging
    Rails.logger.info "Fetching locations for restaurant ID: #{current_restaurant&.id}, include_inactive: #{include_inactive}"
    
    begin
      # Get locations from service
      @locations = location_service.all_locations(include_inactive: include_inactive)
      
      # Log count for debugging
      Rails.logger.info "Found #{@locations.count} locations"
      
      # Explicitly respond with JSON and include the content type
      response.headers['Content-Type'] = 'application/json'
      render json: @locations
    rescue => e
      # Log any errors
      Rails.logger.error "Error in locations#index: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Return a proper JSON error response
      render json: { error: "Could not retrieve locations: #{e.message}" }, status: :internal_server_error
    end
  end
  
  # GET /locations/:id
  def show
    render json: @location
  end
  
  # POST /locations
  def create
    @location = location_service.create_location(location_params)
    
    if @location.persisted?
      render json: @location, status: :created
    else
      render json: { errors: @location.errors }, status: :unprocessable_entity
    end
  end
  
  # PUT /locations/:id
  def update
    @location = location_service.update_location(params[:id], location_params)
    
    if @location&.errors&.empty?
      render json: @location
    else
      render json: { errors: @location&.errors || 'Location not found' }, status: :unprocessable_entity
    end
  end
  
  # DELETE /locations/:id
  def destroy
    result = location_service.delete_location(params[:id])
    
    if result
      head :no_content
    else
      render json: { error: 'Cannot delete this location. It may be the only location, the default location, or have associated orders.' }, 
             status: :unprocessable_entity
    end
  end
  
  # PUT /locations/:id/default
  def set_default
    @location = location_service.set_default_location(params[:id])
    
    if @location
      render json: @location
    else
      render json: { error: 'Location not found' }, status: :not_found
    end
  end
  
  private
  
  def set_location
    @location = location_service.find_location(params[:id])
    
    unless @location
      render json: { error: 'Location not found' }, status: :not_found
    end
  end
  
  def location_params
    params.require(:location).permit(:name, :address, :phone_number, :is_active, :is_default, :email, :description)
  end
  
  def authorize_admin
    unless current_user&.admin? || current_user&.super_admin?
      render json: { error: "Not authorized" }, status: :unauthorized
    end
  end
  
  def location_service
    @location_service ||= LocationService.new(current_restaurant)
  end
end
