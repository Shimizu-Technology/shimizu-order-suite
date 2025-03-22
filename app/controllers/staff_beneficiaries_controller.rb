class StaffBeneficiariesController < ApplicationController
  before_action :authorize_request
  
  def index
    @beneficiaries = StaffBeneficiary.where(restaurant_id: current_user.restaurant_id)
                                     .where(active: true)
                                     .order(:name)
    
    render json: @beneficiaries
  end
  
  def create
    @beneficiary = StaffBeneficiary.new(
      name: params[:name],
      restaurant_id: current_user.restaurant_id
    )
    
    if @beneficiary.save
      render json: @beneficiary, status: :created
    else
      render json: { errors: @beneficiary.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
