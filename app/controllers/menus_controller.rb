# app/controllers/menus_controller.rb
class MenusController < ApplicationController
  before_action :set_menu, only: [:show, :update, :destroy]
  before_action :authorize_request, only: [:set_active, :clone]
  before_action :optional_authorize, only: [:index, :show, :update, :create, :destroy, :set_active, :clone]

  # GET /menus
  def index
    if params[:restaurant_id].present?
      @menus = Menu.where(restaurant_id: params[:restaurant_id])
    else
      @menus = Menu.all
    end
    
    render json: @menus
  end

  # GET /menus/1
  def show
    render json: @menu
  end

  # POST /menus
  def create
    @menu = Menu.new(menu_params)

    if @menu.save
      render json: @menu, status: :created
    else
      render json: { errors: @menu.errors }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /menus/1
  def update
    if @menu.update(menu_params)
      render json: @menu
    else
      render json: { errors: @menu.errors }, status: :unprocessable_entity
    end
  end

  # DELETE /menus/1
  def destroy
    # Check if this is the active menu
    if @menu.restaurant&.current_menu_id == @menu.id
      render json: { error: "Cannot delete the active menu. Please set another menu as active first." }, status: :unprocessable_entity
      return
    end
    
    @menu.destroy
    head :no_content
  end
  
  # POST /menus/:id/set_active
  def set_active
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    
    menu = Menu.find(params[:id])
    restaurant = current_user.restaurant
    
    if restaurant.nil?
      return render json: { error: "User is not associated with a restaurant" }, status: :unprocessable_entity
    end
    
    if menu.restaurant_id != restaurant.id
      return render json: { error: "Menu does not belong to this restaurant" }, status: :unprocessable_entity
    end
    
    # Start a transaction to ensure all updates happen together
    ActiveRecord::Base.transaction do
      # Set all menus for this restaurant to inactive
      restaurant.menus.update_all(active: false)
      
      # Set the selected menu to active
      menu.update!(active: true)
      
      # Update the restaurant's current_menu_id
      restaurant.update!(current_menu_id: menu.id)
    end
    
    render json: { 
      message: "Menu set as active successfully", 
      current_menu_id: restaurant.current_menu_id 
    }
  end
  
  # POST /menus/:id/clone
  def clone
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    
    original_menu = Menu.find(params[:id])
    restaurant = current_user.restaurant
    
    if restaurant.nil?
      return render json: { error: "User is not associated with a restaurant" }, status: :unprocessable_entity
    end
    
    if original_menu.restaurant_id != restaurant.id
      return render json: { error: "Menu does not belong to this restaurant" }, status: :unprocessable_entity
    end
    
    new_menu = Menu.new(
      name: "#{original_menu.name} (Copy)",
      active: false,
      restaurant_id: restaurant.id
    )
    
    if new_menu.save
      # Clone all menu items
      original_menu.menu_items.each do |item|
        new_item = item.dup
        new_item.menu_id = new_menu.id
        new_item.save
        
        # Clone the category associations
        item.menu_item_categories.each do |mic|
          MenuItemCategory.create(
            menu_item_id: new_item.id,
            category_id: mic.category_id
          )
        end
      end
      
      render json: new_menu, status: :created
    else
      render json: { errors: new_menu.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_menu
    @menu = Menu.find(params[:id])
  end

  def menu_params
    params.require(:menu).permit(:name, :active, :restaurant_id)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
  
  # Override the public_endpoint? method from RestaurantScope concern
  def public_endpoint?
    action_name.in?(['index', 'clone', 'set_active', 'update', 'show', 'create', 'destroy'])
  end
end
