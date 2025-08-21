module Wholesale
  module Admin
    class OptionGroupPresetsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_option_group_preset, only: [:show, :update, :destroy, :duplicate, :apply_to_item]
      
      # GET /wholesale/admin/option_group_presets
      def index
        presets = current_restaurant.wholesale_option_group_presets
                                   .includes(:option_presets)
                                   .order(:position, :name)
        
        render_success(
          option_group_presets: presets.map { |preset| option_group_preset_json(preset) },
          total_count: presets.count
        )
      end
      
      # GET /wholesale/admin/option_group_presets/:id
      def show
        render_success(option_group_preset: option_group_preset_json(@option_group_preset))
      end
      
      # POST /wholesale/admin/option_group_presets
      def create
        preset = current_restaurant.wholesale_option_group_presets.build(option_group_preset_params)
        
        if preset.save
          # Create option presets if provided
          if params[:option_presets].present?
            create_option_presets(preset, params[:option_presets])
          end
          
          render_success(
            option_group_preset: option_group_preset_json(preset.reload), 
            message: 'Option group preset created successfully!'
          )
        else
          render_error('Failed to create option group preset', errors: preset.errors.full_messages)
        end
      end
      
      # PATCH/PUT /wholesale/admin/option_group_presets/:id
      def update
        if @option_group_preset.update(option_group_preset_params)
          # Update option presets if provided
          if params[:option_presets].present?
            update_option_presets(@option_group_preset, params[:option_presets])
          end
          
          render_success(
            option_group_preset: option_group_preset_json(@option_group_preset.reload), 
            message: 'Option group preset updated successfully!'
          )
        else
          render_error('Failed to update option group preset', errors: @option_group_preset.errors.full_messages)
        end
      end
      
      # DELETE /wholesale/admin/option_group_presets/:id
      def destroy
        if @option_group_preset.destroy
          render_success(message: 'Option group preset deleted successfully!')
        else
          render_error('Failed to delete option group preset', errors: @option_group_preset.errors.full_messages)
        end
      end
      
      # POST /wholesale/admin/option_group_presets/:id/duplicate
      def duplicate
        begin
          new_preset = @option_group_preset.duplicate!(params[:name])
          render_success(
            option_group_preset: option_group_preset_json(new_preset),
            message: 'Option group preset duplicated successfully!'
          )
        rescue => e
          render_error('Failed to duplicate option group preset', errors: [e.message])
        end
      end
      
      # POST /wholesale/admin/option_group_presets/:id/apply_to_item
      def apply_to_item
        item_id = params[:item_id]
        item = current_restaurant.wholesale_items.find_by(id: item_id)
        
        unless item
          render_not_found('Item not found')
          return
        end
        
        begin
          option_group = @option_group_preset.apply_to_item!(item)
          render_success(
            option_group: option_group_json(option_group),
            message: 'Preset applied to item successfully!'
          )
        rescue => e
          render_error('Failed to apply preset to item', errors: [e.message])
        end
      end
      
      private
      
      def set_option_group_preset
        @option_group_preset = current_restaurant.wholesale_option_group_presets
                                                .includes(:option_presets)
                                                .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Option group preset not found')
      end
      
      def option_group_preset_params
        params.require(:option_group_preset).permit(
          :name, :description, :min_select, :max_select, :required, :position, :enable_inventory_tracking
        )
      end
      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end
      
      def create_option_presets(preset, option_presets_data)
        option_presets_data.each_with_index do |option_data, index|
          preset.option_presets.create!(
            name: option_data[:name],
            additional_price: option_data[:additional_price] || 0,
            available: option_data[:available].nil? ? true : option_data[:available],
            position: option_data[:position] || index
          )
        end
      end
      
      def update_option_presets(preset, option_presets_data)
        # For simplicity, we'll delete all existing option presets and recreate them
        # In a production app, you might want to do a more sophisticated diff/merge
        preset.option_presets.destroy_all
        create_option_presets(preset, option_presets_data)
      end
      
      def option_group_preset_json(preset)
        {
          id: preset.id,
          name: preset.name,
          description: preset.description,
          min_select: preset.min_select,
          max_select: preset.max_select,
          required: preset.required,
          position: preset.position,
          enable_inventory_tracking: preset.enable_inventory_tracking,
          has_available_options: preset.has_available_options?,
          required_but_unavailable: preset.required_but_unavailable?,
          inventory_tracking_enabled: preset.inventory_tracking_enabled?,
          option_presets_count: preset.option_presets.count,
          option_presets: preset.option_presets.order(:position).map { |option| option_preset_json(option) },
          created_at: preset.created_at,
          updated_at: preset.updated_at
        }
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
      
      def option_group_json(option_group)
        {
          id: option_group.id,
          name: option_group.name,
          min_select: option_group.min_select,
          max_select: option_group.max_select,
          required: option_group.required,
          position: option_group.position,
          enable_inventory_tracking: option_group.enable_inventory_tracking,
          has_available_options: option_group.has_available_options?,
          required_but_unavailable: option_group.required_but_unavailable?,
          inventory_tracking_enabled: option_group.inventory_tracking_enabled?,
          total_option_stock: option_group.total_option_stock,
          available_option_stock: option_group.available_option_stock,
          has_option_stock: option_group.has_option_stock?,
          options_count: option_group.options.count,
          options: option_group.options.order(:position).map { |option| option_json(option) },
          created_at: option_group.created_at,
          updated_at: option_group.updated_at
        }
      end
      
      def option_json(option)
        {
          id: option.id,
          name: option.name,
          additional_price: option.additional_price,
          available: option.available,
          position: option.position,
          stock_quantity: option.stock_quantity,
          damaged_quantity: option.damaged_quantity,
          low_stock_threshold: option.low_stock_threshold,
          total_ordered: option.total_ordered,
          total_revenue: option.total_revenue,
          inventory_tracking_enabled: option.inventory_tracking_enabled?,
          available_stock: option.available_stock,
          in_stock: option.in_stock?,
          out_of_stock: option.out_of_stock?,
          low_stock: option.low_stock?,
          final_price: option.final_price,
          display_name: option.display_name,
          full_display_name: option.full_display_name,
          created_at: option.created_at,
          updated_at: option.updated_at
        }
      end
    end
  end
end
