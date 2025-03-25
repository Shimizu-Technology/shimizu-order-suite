# app/controllers/admin/categories_controller.rb

module Admin
  class CategoriesController < ApplicationController
    before_action :authorize_request
    before_action :check_admin!

    # Mark all actions as public endpoints that don't require restaurant context
    def public_endpoint?
      true
    end

    # GET /admin/categories
    def index
      # Filter by menu_id if provided
      categories = if params[:menu_id].present?
                    Menu.find(params[:menu_id]).categories.order(:position, :name)
                  else
                    Category.order(:position, :name)
                  end
      render json: categories
    end

    # POST /admin/categories
    def create
      category = Category.new(category_params)
      if category.save
        render json: category, status: :created
      else
        render json: { errors: category.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /admin/categories/:id
    def update
      category = Category.find(params[:id])
      if category.update(category_params)
        render json: category
      else
        render json: { errors: category.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /admin/categories/:id
    def destroy
      category = Category.find(params[:id])
      category.destroy
      head :no_content
    end

    private

  def category_params
    # Include menu_id and restaurant_id from the URL parameters
    permitted_params = params.require(:category).permit(:name, :position, :description, :menu_id)
    
    # For backward compatibility during transition
    if params[:restaurant_id].present? && !permitted_params[:menu_id].present?
      # If restaurant_id is provided but menu_id is not, use the restaurant's current menu
      restaurant = Restaurant.find(params[:restaurant_id])
      permitted_params[:menu_id] = restaurant.current_menu_id if restaurant.current_menu_id
    end
    
    permitted_params
  end

    def check_admin!
      # if current_user role is admin or super_admin
      render json: { error: "Forbidden" }, status: :forbidden unless current_user&.role.in?(%w[admin super_admin])
    end
  end
end
