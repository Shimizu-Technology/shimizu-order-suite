module Wholesale
  module Admin
    class OptionGroupsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_item
      before_action :set_option_group, only: [:show, :update, :destroy]
      
      # GET /wholesale/admin/items/:item_id/option_groups
      def index
        option_groups = @item.option_groups.includes(:options).order(:position)
        
        render_success(
          option_groups: option_groups.map { |group| option_group_json(group) },
          item: {
            id: @item.id,
            name: @item.name,
            sku: @item.sku,
            has_options: @item.has_options?
          }
        )
      end
      
      # GET /wholesale/admin/items/:item_id/option_groups/:id
      def show
        render_success(option_group: option_group_json(@option_group))
      end
      
      # POST /wholesale/admin/items/:item_id/option_groups
      def create
        option_group = @item.option_groups.build(option_group_params)
        
        if option_group.save
          # Create audit trail if inventory tracking is enabled
          create_option_group_inventory_audit(option_group, 'created')
          
          render_success(
            option_group: option_group_json(option_group), 
            message: 'Option group created successfully!'
          )
        else
          render_error('Failed to create option group', errors: option_group.errors.full_messages)
        end
      end
      
      # PATCH/PUT /wholesale/admin/items/:item_id/option_groups/:id
      def update
        # Track changes for audit trail
        old_enable_inventory_tracking = @option_group.enable_inventory_tracking
        
        if @option_group.update(option_group_params)
          # Create audit trail if inventory tracking was enabled
          create_option_group_inventory_update_audit(@option_group, old_enable_inventory_tracking)
          
          render_success(
            option_group: option_group_json(@option_group), 
            message: 'Option group updated successfully!'
          )
        else
          render_error('Failed to update option group', errors: @option_group.errors.full_messages)
        end
      end
      
      # DELETE /wholesale/admin/items/:item_id/option_groups/:id
      def destroy
        if @option_group.destroy
          render_success(message: 'Option group deleted successfully!')
        else
          render_error('Failed to delete option group', errors: @option_group.errors.full_messages)
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
        @option_group = @item.option_groups.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Option group not found')
      end
      
      def option_group_params
        params.require(:option_group).permit(
          :name, :min_select, :max_select, :required, :position, :enable_inventory_tracking
        )
      end
      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
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

      # Create audit trail for option group inventory setup
      def create_option_group_inventory_audit(option_group, action)
        return unless option_group.enable_inventory_tracking

        # Log that inventory tracking was enabled for this option group
        Rails.logger.info "Option group inventory tracking #{action} for group #{option_group.id} (#{option_group.name}) by user #{current_user.id}"
        
        # Note: Individual option stock audits will be created when options are created/updated
        # This is just for logging the group-level inventory tracking enablement
      rescue => e
        Rails.logger.error "Failed to create option group inventory audit for group #{option_group.id}: #{e.message}"
        # Don't fail the operation if audit fails
      end

      # Create audit trail for option group inventory tracking changes
      def create_option_group_inventory_update_audit(option_group, old_enable_inventory_tracking)
        # Check if inventory tracking was just enabled
        if !old_enable_inventory_tracking && option_group.enable_inventory_tracking
          Rails.logger.info "Option group inventory tracking enabled for group #{option_group.id} (#{option_group.name}) by user #{current_user.id}"
          
          # Create audit records for any existing options with stock quantities
          option_group.options.each do |option|
            if option.stock_quantity.present? && option.stock_quantity > 0
              Wholesale::OptionStockAudit.create!(
                wholesale_option: option,
                audit_type: 'stock_update',
                quantity_change: option.stock_quantity,
                previous_quantity: 0,
                new_quantity: option.stock_quantity,
                reason: "Option-level inventory tracking enabled with existing stock: #{option.stock_quantity} units",
                user: current_user
              )
              
              Rails.logger.info "Created tracking enabled audit for option #{option.id} (#{option.name}): #{option.stock_quantity} units"
            end
          end
        end
      rescue => e
        Rails.logger.error "Failed to create option group inventory update audit for group #{option_group.id}: #{e.message}"
        # Don't fail the operation if audit fails
      end
    end
  end
end