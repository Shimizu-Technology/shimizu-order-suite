module Wholesale
  module Admin
    class OptionsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_item
      before_action :set_option_group
      before_action :set_option, only: [:show, :update, :destroy]
      
      # GET /wholesale/admin/items/:item_id/option_groups/:option_group_id/options
      def index
        options = @option_group.options.order(:position)
        
        render_success(
          options: options.map { |option| option_json(option) },
          option_group: {
            id: @option_group.id,
            name: @option_group.name,
            required: @option_group.required
          },
          item: {
            id: @item.id,
            name: @item.name,
            sku: @item.sku
          }
        )
      end
      
      # GET /wholesale/admin/items/:item_id/option_groups/:option_group_id/options/:id
      def show
        render_success(option: option_json(@option))
      end
      
      # POST /wholesale/admin/items/:item_id/option_groups/:option_group_id/options
      def create
        option = @option_group.options.build(option_params)
        
        if option.save
          render_success(
            option: option_json(option), 
            message: 'Option created successfully!'
          )
        else
          render_error('Failed to create option', errors: option.errors.full_messages)
        end
      end
      
      # PATCH/PUT /wholesale/admin/items/:item_id/option_groups/:option_group_id/options/:id
      def update
        if @option.update(option_params)
          render_success(
            option: option_json(@option), 
            message: 'Option updated successfully!'
          )
        else
          render_error('Failed to update option', errors: @option.errors.full_messages)
        end
      end
      
      # DELETE /wholesale/admin/items/:item_id/option_groups/:option_group_id/options/:id
      def destroy
        if @option.destroy
          render_success(message: 'Option deleted successfully!')
        else
          render_error('Failed to delete option', errors: @option.errors.full_messages)
        end
      end
      
      # PATCH /wholesale/admin/items/:item_id/option_groups/:option_group_id/options/batch_update_positions
      def batch_update_positions
        positions_data = params.require(:positions).map do |item|
          {
            id: item[:id],
            position: item[:position]
          }
        end
        
        updated_count = 0
        errors = []
        
        ActiveRecord::Base.transaction do
          positions_data.each do |position_data|
            option = @option_group.options.find_by(id: position_data[:id])
            if option
              if option.update(position: position_data[:position])
                updated_count += 1
              else
                errors.concat(option.errors.full_messages)
              end
            else
              errors << "Option with ID #{position_data[:id]} not found"
            end
          end
          
          raise ActiveRecord::Rollback if errors.any?
        end
        
        if errors.empty?
          render_success(message: "#{updated_count} options reordered successfully")
        else
          render_error('Failed to update positions', errors: errors)
        end
      end
      
      private
      
      def set_item
        @item = Wholesale::Item.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .find_by(id: params[:item_id])
        render_not_found('Item not found') unless @item
      end
      
      def set_option_group
        @option_group = @item.option_groups.find(params[:option_group_id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Option group not found')
      end
      
      def set_option
        @option = @option_group.options.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Option not found')
      end
      
      def option_params
        params.require(:option).permit(
          :name, :additional_price, :available, :position,
          :stock_quantity, :damaged_quantity, :low_stock_threshold
        )
      end
      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end
      
      def option_json(option)
        {
          id: option.id,
          name: option.name,
          additional_price: option.additional_price,
          available: option.available,
          position: option.position,
          
          # Sales analytics
          total_ordered: option.total_ordered,
          total_revenue: option.total_revenue,
          
          # Future inventory fields
          stock_quantity: option.stock_quantity,
          damaged_quantity: option.damaged_quantity,
          low_stock_threshold: option.low_stock_threshold,
          
          # Computed fields
          inventory_tracking_enabled: option.inventory_tracking_enabled?,
          available_stock: option.available_stock,
          in_stock: option.in_stock?,
          out_of_stock: option.out_of_stock?,
          low_stock: option.low_stock?,
          final_price: option.final_price,
          
          # Display methods
          display_name: option.display_name,
          full_display_name: option.full_display_name,
          
          # Timestamps
          created_at: option.created_at,
          updated_at: option.updated_at,
          
          # Option group info
          option_group: {
            id: option.option_group.id,
            name: option.option_group.name,
            required: option.option_group.required
          }
        }
      end
    end
  end
end