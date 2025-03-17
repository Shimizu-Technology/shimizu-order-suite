# app/controllers/options_controller.rb
class OptionsController < ApplicationController
  before_action :authorize_request
  before_action :set_option, only: [ :update, :destroy ]

  # Mark all actions as public endpoints that don't require restaurant context
  def public_endpoint?
    true
  end

  # POST /option_groups/:option_group_id/options
  def create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    option_group = OptionGroup.find(params[:option_group_id])
    option = option_group.options.build(option_params)

    if option.save
      render json: option.as_json(methods: [ :additional_price_float ]), status: :created
    else
      render json: { errors: option.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /options/:id
  def update
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    if @option.update(option_params)
      render json: @option.as_json(methods: [ :additional_price_float ])
    else
      render json: { errors: @option.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /options/:id
  def destroy
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @option.destroy
    head :no_content
  end

  private

  def set_option
    @option = Option.find(params[:id])
  end

  def option_params
    # Adjust based on your actual Option columns
    params.require(:option).permit(:name, :additional_price, :available)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
