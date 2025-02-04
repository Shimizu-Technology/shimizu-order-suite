class MenusController < ApplicationController
  before_action :authorize_request, except: [:index, :show]

  # GET /menus
  def index
    # If you only want active menus, do `.where(active: true)`
    menus = Menu.all.includes(:menu_items)
    render json: menus.as_json(
      include: {
        menu_items: {
          only: [:id, :name, :description, :price, :available, :image_url, :category]
        }
      }
    )
  end

  # GET /menus/:id
  def show
    menu = Menu.find(params[:id])
    render json: menu.as_json(
      include: {
        menu_items: {
          only: [:id, :name, :description, :price, :available, :image_url, :category]
        }
      }
    )
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
