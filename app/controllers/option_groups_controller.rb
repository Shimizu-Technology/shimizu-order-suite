# app/controllers/option_groups_controller.rb
class OptionGroupsController < ApplicationController
  before_action :authorize_request
  before_action :set_option_group, only: [:update, :destroy]

  # GET /menu_items/:menu_item_id/option_groups
  def index
    # If your MenuItem IDs are integers, make sure `item.id` is numeric in the front end
    menu_item = MenuItem.find(params[:menu_item_id])
    # Eager-load associated options
    option_groups = menu_item.option_groups.includes(:options)

    render json: option_groups.as_json(
      include: {
        options: {
          methods: [:additional_price_float]
        }
      }
    )
  end

  # POST /menu_items/:menu_item_id/option_groups
  def create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:menu_item_id])
    option_group = menu_item.option_groups.build(option_group_params)

    if option_group.save
      render json: option_group.as_json(
        include: {
          options: {
            methods: [:additional_price_float]
          }
        }
      ), status: :created
    else
      render json: { errors: option_group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /option_groups/:id
  def update
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    if @option_group.update(option_group_params)
      render json: @option_group.as_json(
        include: {
          options: {
            methods: [:additional_price_float]
          }
        }
      )
    else
      render json: { errors: @option_group.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /option_groups/:id
  def destroy
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @option_group.destroy
    head :no_content
  end

  private

  def set_option_group
    @option_group = OptionGroup.find(params[:id])
  end

  def option_group_params
    # Adjust permitted params based on your actual OptionGroup columns
    params.require(:option_group).permit(:name, :min_select, :max_select, :required)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
