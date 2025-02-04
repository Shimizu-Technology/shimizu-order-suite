class MenuItemsController < ApplicationController
  before_action :authorize_request, except: [:index, :show]

  # GET /menu_items
  def index
    # Possibly filter by category if params[:category] is passed
    if params[:category].present?
      items = MenuItem.where(category: params[:category]).where(available: true)
    else
      items = MenuItem.where(available: true)
    end
    render json: items
  end

  # GET /menu_items/:id
  def show
    item = MenuItem.find(params[:id])
    render json: item
  end

  # POST /menu_items
  def create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    item = MenuItem.new(menu_item_params)
    if item.save
      render json: item, status: :created
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /menu_items/:id
  def update
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    item = MenuItem.find(params[:id])
    if item.update(menu_item_params)
      render json: item
    else
      render json: { errors: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /menu_items/:id
  def destroy
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    item = MenuItem.find(params[:id])
    item.destroy
    head :no_content
  end

  private

  def menu_item_params
    params.require(:menu_item).permit(:name, :description, :price, :available,
                                      :menu_id, :image_url, :category)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
