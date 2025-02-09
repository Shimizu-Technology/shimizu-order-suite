# app/controllers/orders_controller.rb

class OrdersController < ApplicationController
  before_action :authorize_request, except: [:create, :show]

  # GET /orders
  def index
    if current_user&.role.in?(%w[admin super_admin])
      @orders = Order.includes(:user).all
    elsif current_user
      @orders = current_user.orders
    else
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    render json: @orders, status: :ok
  end

  # GET /orders/:id
  def show
    order = Order.find(params[:id])
    if current_user&.role.in?(%w[admin super_admin]) || current_user&.id == order.user_id
      render json: order
    else
      render json: { error: "Forbidden" }, status: :forbidden
    end
  end

  # POST /orders
  # -- Manual token decoding for optional user association --
  def create
    # 1) If there is an Authorization header, try decoding it manually.
    if request.headers['Authorization'].present?
      token = request.headers['Authorization'].split(' ').last
      begin
        decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
        user_id = decoded[0]['user_id']
        found_user = User.find_by(id: user_id)
        # If we found a valid user, set @current_user or however you track it
        @current_user = found_user if found_user
      rescue JWT::DecodeError
        # If token invalid => do nothing => guest checkout
      end
    end

    # 2) Build the new order params
    new_params = order_params.dup
    new_params[:restaurant_id] ||= 1
    new_params[:user_id] = @current_user&.id if @current_user

    @order = Order.new(new_params)
    @order.status = 'pending'

    # -----------------------------------------------------
    # Check the 'advance_notice_hours' among the items
    # -----------------------------------------------------
    if @order.items.present?
      max_required = 0
      @order.items.each do |item|
        menu_item = MenuItem.find_by(id: item[:id])
        next unless menu_item  # skip if no item found
        max_required = [max_required, menu_item.advance_notice_hours].max
      end

      # Optionally, if the client didn't provide an estimated_pickup_time, we can set one:
      # if @order.estimated_pickup_time.blank?
      #   @order.estimated_pickup_time = Time.current + (max_required >= 24 ? 24.hours : 20.minutes)
      # end

      if max_required >= 24 && @order.estimated_pickup_time.present?
        earliest_allowed = Time.current + 24.hours
        if @order.estimated_pickup_time < earliest_allowed
          return render json: {
            error: "Earliest pickup time for these items is at least #{earliest_allowed.strftime('%Y-%m-%d %H:%M')}"
          }, status: :unprocessable_entity
        end
      end
    end

    # 3) Attempt to save
    if @order.save
      render json: @order, status: :created
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /orders/:id
  def update
    order = Order.find(params[:id])
    return render json: { error: "Forbidden" }, status: :forbidden unless can_edit?(order)

    if order.update(order_params)
      render json: order
    else
      render json: { errors: order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /orders/:id
  def destroy
    order = Order.find(params[:id])
    return render json: { error: "Forbidden" }, status: :forbidden unless can_edit?(order)

    order.destroy
    head :no_content
  end

  private

  def order_params
    # items: [ { "id": 7, "name": "Onion Rings", "price": 13.95, "quantity": 1 }, ... ]
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
    current_user&.role.in?(%w[admin super_admin]) ||
      (current_user && order.user_id == current_user.id)
  end
end
