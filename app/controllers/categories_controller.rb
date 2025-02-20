# app/controllers/categories_controller.rb
class CategoriesController < ApplicationController
  # No admin requirement here, so all users (or guests) can call index:
  before_action :optional_authorize, only: [:index]

  # GET /categories
  def index
    categories = Category.order(:name)
    render json: categories
  end
end
