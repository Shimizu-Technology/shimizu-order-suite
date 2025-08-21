module Wholesale
  module Admin
    class OptionPresetsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_option_group_preset
      before_action :set_option_preset, only: [:show, :update, :destroy]
      
      # GET /wholesale/admin/option_group_presets/:option_group_preset_id/option_presets
      def index
        option_presets = @option_group_preset.option_presets.order(:position, :name)
        
        render_success(
          option_presets: option_presets.map { |preset| option_preset_json(preset) },
          option_group_preset: {
            id: @option_group_preset.id,
            name: @option_group_preset.name,
            description: @option_group_preset.description
          }
        )
      end
      
      # GET /wholesale/admin/option_group_presets/:option_group_preset_id/option_presets/:id
      def show
        render_success(option_preset: option_preset_json(@option_preset))
      end
      
      # POST /wholesale/admin/option_group_presets/:option_group_preset_id/option_presets
      def create
        option_preset = @option_group_preset.option_presets.build(option_preset_params)
        
        if option_preset.save
          render_success(
            option_preset: option_preset_json(option_preset), 
            message: 'Option preset created successfully!'
          )
        else
          render_error('Failed to create option preset', errors: option_preset.errors.full_messages)
        end
      end
      
      # PATCH/PUT /wholesale/admin/option_group_presets/:option_group_preset_id/option_presets/:id
      def update
        if @option_preset.update(option_preset_params)
          render_success(
            option_preset: option_preset_json(@option_preset), 
            message: 'Option preset updated successfully!'
          )
        else
          render_error('Failed to update option preset', errors: @option_preset.errors.full_messages)
        end
      end
      
      # DELETE /wholesale/admin/option_group_presets/:option_group_preset_id/option_presets/:id
      def destroy
        if @option_preset.destroy
          render_success(message: 'Option preset deleted successfully!')
        else
          render_error('Failed to delete option preset', errors: @option_preset.errors.full_messages)
        end
      end
      
      private
      
      def set_option_group_preset
        @option_group_preset = current_restaurant.wholesale_option_group_presets
                                                .find(params[:option_group_preset_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Option group preset not found')
      end
      
      def set_option_preset
        @option_preset = @option_group_preset.option_presets.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Option preset not found')
      end
      
      def option_preset_params
        params.require(:option_preset).permit(
          :name, :additional_price, :available, :position
        )
      end
      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end
      
      def option_preset_json(option)
        {
          id: option.id,
          name: option.name,
          additional_price: option.additional_price,
          available: option.available,
          position: option.position,
          display_name: option.display_name,
          full_display_name: option.full_display_name,
          created_at: option.created_at,
          updated_at: option.updated_at
        }
      end
    end
  end
end
