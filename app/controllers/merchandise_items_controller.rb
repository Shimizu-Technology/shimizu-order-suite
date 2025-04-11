class MerchandiseItemsController < ApplicationController
  include TenantIsolation
  
  # For index & show, we skip the tenant context check to allow public access
  skip_before_action :set_current_tenant, only: [:index, :show]
  
  # For public actions, ensure we still have a restaurant context
  before_action :ensure_restaurant_context, only: [:index, :show]
  
  # For other actions, require token + admin
  before_action :authorize_request, except: [:index, :show]
  
  # Override global_access_permitted to allow public access to index and show
  def global_access_permitted?
    action_name.in?(["index", "show"])
  end
  
  # GET /merchandise_items
  def index
    result = merchandise_item_service.list_items(params, current_user)
    
    if result[:success]
      render json: result[:items]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :internal_server_error
    end
  end
  
  # GET /merchandise_items/:id
  def show
    result = merchandise_item_service.get_item(params[:id])
    
    if result[:success]
      render json: result[:item]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :not_found
    end
  end
  
  # POST /merchandise_items
  def create
    Rails.logger.info "=== MerchandiseItemsController#create ==="
    
    result = merchandise_item_service.create_item(merchandise_item_params, current_user)
    
    if result[:success]
      Rails.logger.info "Created MerchandiseItem => #{result[:item].inspect}"
      render json: result[:item], status: :created
    else
      Rails.logger.info "Failed to create => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # PATCH/PUT /merchandise_items/:id
  def update
    Rails.logger.info "=== MerchandiseItemsController#update ==="
    
    result = merchandise_item_service.update_item(params[:id], merchandise_item_params, current_user)
    
    if result[:success]
      Rails.logger.info "Update success => #{result[:item].inspect}"
      render json: result[:item]
    else
      Rails.logger.info "Update failed => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # DELETE /merchandise_items/:id
  def destroy
    Rails.logger.info "=== MerchandiseItemsController#destroy ==="
    
    result = merchandise_item_service.delete_item(params[:id], current_user)
    
    if result[:success]
      Rails.logger.info "Destroyed MerchandiseItem => #{params[:id]}"
      head :no_content
    else
      Rails.logger.info "Failed to destroy => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /merchandise_items/:id/upload_image
  def upload_image
    Rails.logger.info "=== MerchandiseItemsController#upload_image ==="
    
    result = merchandise_item_service.upload_image(params[:id], params[:image], current_user)
    
    if result[:success]
      Rails.logger.info "merchandise_item updated => image_url: #{result[:item].image_url.inspect}"
      render json: result[:item], status: :ok
    else
      Rails.logger.info "Failed to upload image => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  # POST /merchandise_items/:id/upload_second_image
  def upload_second_image
    Rails.logger.info "=== MerchandiseItemsController#upload_second_image ==="
    
    result = merchandise_item_service.upload_image(params[:id], params[:image], current_user, true)
    
    if result[:success]
      Rails.logger.info "merchandise_item updated => second_image_url: #{result[:item].second_image_url.inspect}"
      render json: result[:item], status: :ok
    else
      Rails.logger.info "Failed to upload second image => #{result[:errors].inspect}"
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end
  
  private
  
  def merchandise_item_params
    params.require(:merchandise_item).permit(
      :name,
      :description,
      :base_price,
      :available,
      :merchandise_collection_id,
      :image_url,
      :image,
      :second_image_url,
      :second_image,
      :stock_status,
      :low_stock_threshold,
      :status_note
    )
  end
  
  def merchandise_item_service
    # Make sure we have a restaurant context, even for public actions
    ensure_restaurant_context if action_name.in?(["index", "show"])
    
    # Use the thread-local restaurant context if current_restaurant is nil
    restaurant = current_restaurant || ActiveRecord::Base.current_restaurant
    
    # Ensure we have a restaurant before initializing the service
    if restaurant.nil?
      Rails.logger.error "No restaurant context available for MerchandiseItemService"
      raise "Restaurant context is required for merchandise item operations"
    end
    
    @merchandise_item_service ||= MerchandiseItemService.new(restaurant, analytics)
  end
  
  # Ensure we have a restaurant context for public actions
  def ensure_restaurant_context
    return if ActiveRecord::Base.current_restaurant
    
    # Find the restaurant from params or use the first one in development
    restaurant_id = params[:restaurant_id]
    Rails.logger.info "Attempting to set restaurant context with ID: #{restaurant_id || 'nil (using first)'}"
    
    restaurant = if restaurant_id
                  Restaurant.find_by(id: restaurant_id)
                else
                  Restaurant.first
                end
    
    if restaurant
      # Set the current tenant context
      Rails.logger.info "Setting tenant context to restaurant_id: #{restaurant.id}"
      ActiveRecord::Base.current_restaurant = restaurant
    else
      Rails.logger.error "Failed to find restaurant with ID: #{restaurant_id || 'nil (first)'}"
    end
  end
end
