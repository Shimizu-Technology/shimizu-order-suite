# app/controllers/menus_controller.rb
class MenusController < ApplicationController
  before_action :authorize_request, except: [:index, :show]
  
  # Mark index and show as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?(['index', 'show'])
  end

  # GET /menus
  def index
    menus = Menu.includes(:menu_items)
    # No need for complicated includes now that we override as_json
    render json: menus
  end

  # GET /menus/:id
  def show
    menu = Menu.find(params[:id])
    render json: menu
  end

  # POST /menus
  def create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    menu = Menu.new(menu_params)
    if menu.save
      render json: menu, status: :created
    else
      render json: { errors: menu.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /menus/:id
  def update
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    menu = Menu.find(params[:id])
    if menu.update(menu_params)
      render json: menu
    else
      render json: { errors: menu.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /menus/:id
  def destroy
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    menu = Menu.find(params[:id])
    menu.destroy
    head :no_content
  end

  private

  def menu_params
    params.require(:menu).permit(:name, :active, :restaurant_id)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
