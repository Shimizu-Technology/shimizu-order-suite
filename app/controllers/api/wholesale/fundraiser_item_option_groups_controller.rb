# app/controllers/api/wholesale/fundraiser_item_option_groups_controller.rb
module Api
  module Wholesale
    class FundraiserItemOptionGroupsController < ApplicationController
      include TenantIsolation
      
      before_action :authorize_request, except: [:index]
      before_action :optional_authorize, only: [:index]
      before_action :ensure_tenant_context

      # GET /api/wholesale/fundraisers/:fundraiser_id/items/:item_id/option_groups
      def index
        option_groups = OptionGroup.where(optionable_type: 'FundraiserItem', optionable_id: params[:item_id])
                                  .includes(:options)

        render json: option_groups.as_json(
          include: {
            options: {
              methods: [:additional_price_float]
            }
          }
        )
      end

      # POST /api/wholesale/fundraisers/:fundraiser_id/items/:item_id/option_groups
      def create
        fundraiser_item = FundraiserItem.find(params[:item_id])
        
        # Ensure user has access to this fundraiser item via Pundit
        authorize(fundraiser_item, :update?)
        
        # Create the option group
        # We can now use the polymorphic association properly since menu_item_id can be null
        option_group = fundraiser_item.option_groups.new(option_group_params)
        
        # Get options parameters without triggering unpermitted parameter warnings
        # by explicitly permitting them through a custom permit method
        options_params = if params[:fundraiser_item_option_group].present? && params[:fundraiser_item_option_group][:options].present?
          # Extract from nested parameters
          params[:fundraiser_item_option_group][:options]
        elsif params[:options].present?
          # Extract from root level parameters
          params[:options]
        else
          []
        end
        
        # Process options if they exist
        if options_params.present?
          ActiveRecord::Base.transaction do
            if option_group.save
              # Create options for the group
              options_params.each do |option_param|
                # Skip id if it's negative (frontend temp id)
                # Convert hash to parameters object if needed
                option_param_obj = option_param.is_a?(ActionController::Parameters) ? option_param : ActionController::Parameters.new(option_param)
                
                # Extract permitted attributes
                option_attrs = {}
                [:name, :additional_price, :position, :is_preselected, :is_available].each do |attr|
                  option_attrs[attr] = option_param_obj[attr] if option_param_obj[attr].present?
                end
                
                option_group.options.create!(option_attrs)
              end
              
              render json: option_group, include: :options
            else
              render json: { errors: option_group.errors.full_messages }, status: :unprocessable_entity
              raise ActiveRecord::Rollback
            end
          end
        else
          # No options to process
          if option_group.save
            render json: option_group
          else
            render json: { errors: option_group.errors.full_messages }, status: :unprocessable_entity
          end
        end
      end

      # PATCH /api/wholesale/option_groups/:id
      def update
        option_group = OptionGroup.find(params[:id])
        
        # Ensure user has access to this option group via tenant isolation
        authorize_access_to(option_group)
        
        if option_group.update(option_group_params)
          render json: option_group.as_json(
            include: {
              options: {
                methods: [:additional_price_float]
              }
            }
          )
        else
          render json: { errors: option_group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/wholesale/option_groups/:id
      def destroy
        option_group = OptionGroup.find(params[:id])
        
        # Ensure user has access to this option group via tenant isolation
        authorize_access_to(option_group)
        
        if option_group.destroy
          head :no_content
        else
          render json: { errors: option_group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/wholesale/option_groups/:id/reorder
      def reorder
        option_group = OptionGroup.find(params[:id])
        
        # Ensure user has access to this option group via tenant isolation
        authorize_access_to(option_group)
        
        if option_group.update(position: params[:position])
          head :no_content
        else
          render json: { errors: option_group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def option_group_params
        # Check if parameters are sent under fundraiser_item_option_group key
        if params[:fundraiser_item_option_group].present?
          # Exclude position since it's not a column in the database
          params.require(:fundraiser_item_option_group).permit(:name, :min_select, :max_select, :free_option_count)
        # Fall back to direct parameters if they exist
        elsif params[:name].present?
          # Exclude position since it's not a column in the database
          params.permit(:name, :min_select, :max_select, :free_option_count)
        else
          # If neither format is found, raise an error
          raise ActionController::ParameterMissing.new(:option_group)
        end
      end
    end
  end
end
