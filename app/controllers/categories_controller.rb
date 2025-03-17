# app/controllers/categories_controller.rb
class CategoriesController < ApplicationController
  # No admin requirement here, so all users (or guests) can call index:
  before_action :optional_authorize, only: [ :index ]

  # Mark index as a public endpoint that doesn't require restaurant context
  def public_endpoint?
    action_name == "index"
  end

  # GET /categories
  def index
    categories = Category.order(:name)
    render json: categories
  end
end
