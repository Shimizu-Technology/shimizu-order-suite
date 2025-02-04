# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :authorize_request, except: [:create, :show]

  # GET /orders
  #   Admin can see all, a normal user sees only their own
  def index
    if current_user&.role.in?(%w[admin super_admin])
      @orders = Order.includes(:user).all
    elsif current_user
      @orders = current_user.orders
    else
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    # This will automatically use Order#as_json, so `total` is numeric.
    render json: @orders, status: :ok
  end

  # GET /orders/:id
  def show
    order = Order.find(params[:id])
    # Ensure only admin or user who created the order can view it
    if current_user&.role.in?(%w[admin super_admin]) || current_user&.id == order.user_id
      render json: order  # calls as_json => numeric total
    else
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end

  # POST /orders
  #   A user or guest can create an order. If `user_id` is not present,
  #   we treat it as guest checkout. The front-end would pass items, total, etc.
  def create
    # default to a known restaurant_id if not provided
    # or the client must send { order: { restaurant_id: 1, ... } }
    new_params = order_params.dup
    new_params[:restaurant_id] ||= 1

    # If we have a logged-in user
    new_params[:user_id] = current_user.id if current_user

    @order = Order.new(new_params)
    @order.status = "pending"  # or 'preparing' if paid, etc.

    if @order.save
      # Overridden as_json => numeric total
      render json: @order, status: :created
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /orders/:id
  #   Typically admin changes order status: pending -> preparing -> ready -> completed / cancelled
  def update
    order = Order.find(params[:id])
    return render json: { error: "Forbidden" }, status: :forbidden unless can_edit?(order)

    if order.update(order_params)
      render json: order  # calls as_json => numeric total
    else
      render json: { errors: order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /orders/:id
  #   Usually not recommended to truly delete orders, but up to you.
  def destroy
    order = Order.find(params[:id])
    return render json: { error: "Forbidden" }, status: :forbidden unless can_edit?(order)

    order.destroy
    head :no_content
  end

  private

  def order_params
    # items: [ { "id": "", "name": "", "quantity": 1, "price": 12.34, "customizations": {...} }, ... ]
    # special_instructions, promo_code, total, estimated_pickup_time, etc.
    params.require(:order).permit(
      :restaurant_id,
      :user_id,
      :status,
      :total,
      :promo_code,
      :special_instructions,
      :estimated_pickup_time,
      items: [:id, :name, :price, :quantity, customizations: {}]
    )
  end

  def can_edit?(order)
    # admin or the user who created it
    current_user&.role.in?(%w[admin super_admin]) || order.user_id == current_user&.id
  end
end
