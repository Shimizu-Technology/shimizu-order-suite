# app/controllers/categories_controller.rb
class CategoriesController < ApplicationController
  # Skip the restaurant scope filter - we'll handle it manually after authentication
  skip_before_action :set_restaurant_scope, only: [:create, :update, :destroy]
  
  # No admin requirement here, so all users (or guests) can call index:
  before_action :optional_authorize, only: [:index]
  before_action :authorize_request, only: [:create, :update, :destroy]
  before_action :set_menu, only: [:index, :create, :update, :destroy]
  before_action :set_category, only: [:update, :destroy]
  # Call set_restaurant_scope manually after authentication
  before_action :set_restaurant_scope, only: [:create, :update, :destroy]
  
  # Mark index as a public endpoint that doesn't require restaurant context
  def public_endpoint?
    action_name == "index"
  end
  
  # GET /menus/:menu_id/categories
  def index
    categories = @menu ? @menu.categories.order(:position, :name) : Category.order(:position, :name)
    render json: categories
  end
  
  # POST /menus/:menu_id/categories
  def create
    category = @menu.categories.build(category_params)
    
    if category.save
      render json: category, status: :created
    else
      render json: { errors: category.errors }, status: :unprocessable_entity
    end
  end
  
  # PATCH/PUT /menus/:menu_id/categories/:id
  def update
    if @category.update(category_params)
      render json: @category
    else
      render json: { errors: @category.errors }, status: :unprocessable_entity
    end
  end
  
  # DELETE /menus/:menu_id/categories/:id
  def destroy
    if @category.menu_items.empty?
      @category.destroy
      head :no_content
    else
      render json: { error: "Cannot delete category with associated menu items" }, status: :unprocessable_entity
    end
  end
  
  private
  
  def set_menu
    @menu = Menu.find(params[:menu_id]) if params[:menu_id]
  end
  
  def set_category
    @category = @menu.categories.find(params[:id])
  end
  
  def category_params
    params.require(:category).permit(:name, :position, :description)
  end
end
