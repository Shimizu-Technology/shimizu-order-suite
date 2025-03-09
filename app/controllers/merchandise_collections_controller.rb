class MerchandiseCollectionsController < ApplicationController
  before_action :set_merchandise_collection, only: [:show, :update, :destroy]
  before_action :authorize_request, only: [:set_active]
  before_action :optional_authorize, only: [:index, :show, :update, :create, :destroy, :set_active]

  # GET /merchandise_collections
  def index
    if params[:restaurant_id].present?
      @collections = MerchandiseCollection.where(restaurant_id: params[:restaurant_id]).order(created_at: :asc)
    else
      @collections = MerchandiseCollection.all.order(created_at: :asc)
    end
    
    render json: @collections
  end

  # GET /merchandise_collections/1
  def show
    render json: @merchandise_collection, include_items: true
  end

  # POST /merchandise_collections
  def create
    @merchandise_collection = MerchandiseCollection.new(merchandise_collection_params)

    if @merchandise_collection.save
      render json: @merchandise_collection, status: :created
    else
      render json: { errors: @merchandise_collection.errors }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /merchandise_collections/1
  def update
    if @merchandise_collection.update(merchandise_collection_params)
      render json: @merchandise_collection
    else
      render json: { errors: @merchandise_collection.errors }, status: :unprocessable_entity
    end
  end

  # DELETE /merchandise_collections/1
  def destroy
    # Check if this is the active collection
    if @merchandise_collection.restaurant&.current_merchandise_collection_id == @merchandise_collection.id
      render json: { error: "Cannot delete the active collection. Please set another collection as active first." }, status: :unprocessable_entity
      return
    end
    
    @merchandise_collection.destroy
    head :no_content
  end
  
  # POST /merchandise_collections/:id/set_active
  def set_active
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    
    collection = MerchandiseCollection.find(params[:id])
    restaurant = current_user.restaurant
    
    if restaurant.nil?
      return render json: { error: "User is not associated with a restaurant" }, status: :unprocessable_entity
    end
    
    if collection.restaurant_id != restaurant.id
      return render json: { error: "Collection does not belong to this restaurant" }, status: :unprocessable_entity
    end
    
    # Start a transaction to ensure all updates happen together
    ActiveRecord::Base.transaction do
      # Set all collections for this restaurant to inactive
      restaurant.merchandise_collections.update_all(active: false)
      
      # Set the selected collection to active
      collection.update!(active: true)
      
      # Update the restaurant's current_merchandise_collection_id
      restaurant.update!(current_merchandise_collection_id: collection.id)
    end
    
    render json: { 
      message: "Collection set as active successfully", 
      current_merchandise_collection_id: restaurant.current_merchandise_collection_id 
    }
  end

  private

  def set_merchandise_collection
    @merchandise_collection = MerchandiseCollection.find(params[:id])
  end

  def merchandise_collection_params
    params.require(:merchandise_collection).permit(:name, :description, :active, :restaurant_id)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
  
  # Override the public_endpoint? method from RestaurantScope concern
  def public_endpoint?
    action_name.in?(['index', 'set_active', 'update', 'show', 'create', 'destroy'])
  end
end
