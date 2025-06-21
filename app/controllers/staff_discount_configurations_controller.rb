class StaffDiscountConfigurationsController < ApplicationController
  before_action :optional_authorize, only: [:index]
  before_action :authorize_request, except: [:index]
  before_action :require_admin!, except: [:index]
  before_action :set_staff_discount_configuration, only: [:show, :update, :destroy]

  # GET /staff_discount_configurations
  # Public endpoint for fetching active discount configurations (used by frontend)
  def index
    @configurations = current_restaurant.staff_discount_configurations
                                        .active
                                        .ordered
    
    render json: {
      staff_discount_configurations: @configurations.map(&:to_api_hash)
    }
  end

  # GET /staff_discount_configurations/admin
  # Admin endpoint for fetching all configurations (active and inactive)
  def admin_index
    @configurations = current_restaurant.staff_discount_configurations.ordered
    
    render json: {
      staff_discount_configurations: @configurations.map(&:to_api_hash)
    }
  end

  # GET /staff_discount_configurations/:id
  def show
    render json: { staff_discount_configuration: @configuration.to_api_hash }
  end

  # POST /staff_discount_configurations
  def create
    @configuration = current_restaurant.staff_discount_configurations.build(configuration_params)

    if @configuration.save
      render json: {
        staff_discount_configuration: @configuration.to_api_hash
      }, status: :created
    else
      Rails.logger.error "StaffDiscountConfiguration creation failed: #{@configuration.errors.full_messages.join(', ')}"
      Rails.logger.error "Attempted params: #{configuration_params.inspect}"
      Rails.logger.error "Sanitized code would be: '#{@configuration.code}'"
      Rails.logger.error "Restaurant ID: #{current_restaurant.id}"
      Rails.logger.error "Existing codes for this restaurant: #{current_restaurant.staff_discount_configurations.pluck(:code).inspect}"
      Rails.logger.error "Detailed errors: #{@configuration.errors.details.inspect}"
      
      render json: {
        errors: @configuration.errors.full_messages,
        details: @configuration.errors.details
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /staff_discount_configurations/:id
  def update
    if @configuration.update(configuration_params)
      render json: {
        staff_discount_configuration: @configuration.to_api_hash
      }
    else
      render json: {
        errors: @configuration.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /staff_discount_configurations/:id
  def destroy
    begin
      @configuration.destroy
      head :no_content
    rescue ActiveRecord::InvalidForeignKey => e
      Rails.logger.error "Cannot delete staff discount configuration #{@configuration.id}: #{e.message}"
      
      # Check if there are orders using this configuration
      orders_count = Order.where(staff_discount_configuration_id: @configuration.id).count
      
      render json: {
        errors: ["Cannot delete this discount configuration because it is being used by #{orders_count} existing order(s). You can deactivate it instead."],
        suggestion: "deactivate"
      }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error "Error deleting staff discount configuration #{@configuration.id}: #{e.message}"
      
      render json: {
        errors: ["An error occurred while deleting the discount configuration."]
      }, status: :internal_server_error
    end
  end

  private

  def set_staff_discount_configuration
    @configuration = current_restaurant.staff_discount_configurations.find(params[:id])
  end

  def configuration_params
    params.require(:staff_discount_configuration).permit(
      :name, :code, :discount_percentage, :discount_type, :is_active, 
      :is_default, :display_order, :description, :ui_color
    )
  end


end 