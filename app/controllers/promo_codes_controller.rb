# app/controllers/promo_codes_controller.rb
class PromoCodesController < ApplicationController
  before_action :authorize_request, except: [ :index, :show ]

  # Mark index and show as public endpoints that don't require restaurant context
  def public_endpoint?
    action_name.in?([ "index", "show" ])
  end

  # GET /promo_codes
  #   Maybe only admin sees them all. Or you can let normal users see them (for applying promos).
  def index
    if current_user&.role.in?(%w[admin super_admin])
      @promo_codes = PromoCode.all
    else
      @promo_codes = PromoCode.where("valid_until > ? OR valid_until IS NULL", Time.now)
    end
    render json: @promo_codes
  end

  # GET /promo_codes/:id or /promo_codes/:code
  def show
    code = PromoCode.find_by(code: params[:id]) || PromoCode.find(params[:id])
    render json: code
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Promo code not found" }, status: :not_found
  end

  # POST /promo_codes (admin only)
  def create
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    code = PromoCode.new(promo_code_params)
    if code.save
      render json: code, status: :created
    else
      render json: { errors: code.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /promo_codes/:id
  def update
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    code = PromoCode.find(params[:id])
    if code.update(promo_code_params)
      render json: code
    else
      render json: { errors: code.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /promo_codes/:id
  def destroy
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?
    code = PromoCode.find(params[:id])
    code.destroy
    head :no_content
  end

  private

  def promo_code_params
    params.require(:promo_code).permit(:code, :discount_percent, :valid_from, :valid_until,
                                       :max_uses, :current_uses, :restaurant_id)
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
