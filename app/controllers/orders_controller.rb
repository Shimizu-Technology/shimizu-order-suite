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

  # GET /orders/new_since/:id
  def new_since
    unless current_user&.role.in?(%w[admin super_admin])
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    last_id = params[:id].to_i
    new_orders = Order.where("id > ?", last_id).order(:id)
    render json: new_orders, status: :ok
  end

  # POST /orders
  def create
    # Optional manual token decode for guest checkout w/ token
    if request.headers['Authorization'].present?
      token = request.headers['Authorization'].split(' ').last
      begin
        decoded    = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
        user_id    = decoded[0]['user_id']
        found_user = User.find_by(id: user_id)
        @current_user = found_user if found_user
      rescue JWT::DecodeError
        # invalid token => do nothing => guest
      end
    end

    new_params = order_params.dup
    new_params[:restaurant_id] ||= 1
    # If there's a logged-in user, attach them
    new_params[:user_id] = @current_user&.id

    @order = Order.new(new_params)
    @order.status = 'pending'

    # -----------------------------------------------------
    # Check the 'advance_notice_hours' among the items
    # -----------------------------------------------------
    if @order.items.present?
      max_required = 0
      @order.items.each do |item|
        menu_item = MenuItem.find_by(id: item[:id])
        next unless menu_item
        max_required = [max_required, menu_item.advance_notice_hours].max
      end

      # If no estimated_pickup_time was provided, you could auto-set here:
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

    # Attempt to save
    if @order.save
      # 1) Confirmation email
      if @order.contact_email.present?
        OrderMailer.order_confirmation(@order).deliver_later
      end

      # 2) Confirmation text
      if @order.contact_phone.present?
        item_list = @order.items.map { |i| "#{i['quantity']}x #{i['name']}" }.join(", ")
        pickup_str = if @order.estimated_pickup_time.present?
                        "Pickup around #{@order.estimated_pickup_time.strftime('%-I:%M %p')}."
                      else
                        "We'll let you know once it's ready!"
                      end
        message_body = <<~MSG.squish
          Hi #{@order.contact_name.presence || 'Customer'},
          thanks for ordering from Hafaloha!
          Order ##{@order.id}: #{item_list}, total: $#{@order.total.to_f.round(2)}.
          #{pickup_str}
        MSG

        ClicksendClient.send_text_message(
          to:   @order.contact_phone,
          body: message_body,
          from: 'Hafaloha'
        )
      end

      render json: @order, status: :created
    else
      render json: { errors: @order.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /orders/:id
  def update
    order = Order.find(params[:id])
    return render json: { error: "Forbidden" }, status: :forbidden unless can_edit?(order)

    old_status = order.status
    if order.update(order_params)
      # ---------------------------------------------------
      # Check if status changed => e.g. to "ready"
      # ---------------------------------------------------
      if old_status != 'ready' && order.status == 'ready'
        # or use "ready" if that’s the status you prefer
        # 1) Email
        if order.contact_email.present?
          OrderMailer.order_ready(order).deliver_later
        end
        # 2) SMS
        if order.contact_phone.present?
          msg = <<~TXT.squish
            Hi #{order.contact_name.presence || 'Customer'},
            Your order ##{order.id} is now ready for pickup!
            Thank you for choosing Hafaloha!
          TXT
          ClicksendClient.send_text_message(
            to:   order.contact_phone,
            body: msg,
            from: 'Hafaloha'
          )
        end
      end

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
    params.require(:order).permit(
      :restaurant_id,
      :user_id,
      :status,
      :total,
      :promo_code,
      :special_instructions,
      :estimated_pickup_time,
      :contact_name,
      :contact_phone,
      :contact_email,
      items: [
        :id,
        :name,
        :price,
        :quantity,
        :notes,
        { customizations: {} }
      ]
    )
  end

  def can_edit?(order)
    return true if current_user&.role.in?(%w[admin super_admin])
    current_user && order.user_id == current_user.id
  end
end
