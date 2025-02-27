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
      # Could also sort by :position, :name, etc.
      categories = Category.order(:name)
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
      # Include restaurant_id from the URL parameter
      permitted_params = params.require(:category).permit(:name, :position)
      permitted_params[:restaurant_id] = params[:restaurant_id] if params[:restaurant_id].present?
      permitted_params
    end

    def check_admin!
      # if current_user role is admin or super_admin
      render json: { error: "Forbidden" }, status: :forbidden unless current_user&.role.in?(%w[admin super_admin])
    end
  end
end
