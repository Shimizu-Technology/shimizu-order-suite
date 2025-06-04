# app/controllers/api/wholesale/fundraiser_item_options_controller.rb
module Api
  module Wholesale
    class FundraiserItemOptionsController < ApplicationController
      include TenantIsolation
      
      before_action :authorize_request
      before_action :ensure_tenant_context

      # GET /api/wholesale/option_groups/:option_group_id/options
      def index
        option_group = OptionGroup.find(params[:option_group_id])
        
        # Ensure user has access to this option group via tenant isolation
        authorize_access_to(option_group)
        
        options = option_group.options.order(position: :asc)
        
        render json: options.as_json(methods: [:additional_price_float])
      end

      # POST /api/wholesale/option_groups/:option_group_id/options
      def create
        option_group = OptionGroup.find(params[:option_group_id])
        
        # Ensure user has access to this option group via tenant isolation
        authorize_access_to(option_group)
        
        option = option_group.options.new(option_params)
        
        if option.save
          render json: option.as_json(methods: [:additional_price_float]), status: :created
        else
          render json: { errors: option.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/wholesale/options/:id
      def update
        option = Option.find(params[:id])
        
        # Ensure user has access to this option via tenant isolation
        authorize_access_to(option)
        
        if option.update(option_params)
          render json: option.as_json(methods: [:additional_price_float])
        else
          render json: { errors: option.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/wholesale/options/:id
      def destroy
        option = Option.find(params[:id])
        
        # Ensure user has access to this option via tenant isolation
        authorize_access_to(option)
        
        if option.destroy
          head :no_content
        else
          render json: { errors: option.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/wholesale/options/:id/reorder
      def reorder
        option = Option.find(params[:id])
        
        # Ensure user has access to this option via tenant isolation
        authorize_access_to(option)
        
        if option.update(position: params[:position])
          head :no_content
        else
          render json: { errors: option.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/wholesale/options/:id/toggle_availability
      def toggle_availability
        option = Option.find(params[:id])
        
        # Ensure user has access to this option via tenant isolation
        authorize_access_to(option)
        
        if option.update(is_available: !option.is_available)
          render json: option.as_json(methods: [:additional_price_float])
        else
          render json: { errors: option.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private
      
      # Authorize access to a resource based on tenant isolation
      # This ensures that users can only access options from their own tenant
      def authorize_access_to(resource)
        if resource.is_a?(Option)
          # For an option, check its option_group's optionable association
          option_group = resource.option_group
          
          if option_group.optionable_type == 'FundraiserItem'
            # If it's linked to a FundraiserItem, authorize via Pundit
            fundraiser_item = FundraiserItem.find_by(id: option_group.optionable_id)
            authorize(fundraiser_item, :update?) if fundraiser_item
          else
            # For other optionable types, check tenant context matches
            unless option_group.restaurant_id == current_restaurant&.id
              raise Pundit::NotAuthorizedError, "Not authorized to access this option"
            end
          end
        else
          # For other resource types, implement as needed
          raise Pundit::NotAuthorizedError, "Not authorized to access this resource"
        end
      end

      def option_params
        params.require(:option).permit(:name, :additional_price, :is_preselected, :is_available, :position)
      end
    end
  end
end
