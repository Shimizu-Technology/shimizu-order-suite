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
          # Create audit trail for initial option inventory setup
          create_option_inventory_audit(option, 'created')
          
          # Auto-expand variants if the item has variant tracking enabled
          if @item.track_variants?
            expand_variants_for_new_option(option)
          end
          
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
        # Track changes for audit trail
        old_stock_quantity = @option.stock_quantity
        
        if @option.update(option_params)
          # Create audit trail for option inventory changes
          create_option_inventory_update_audit(@option, old_stock_quantity)
          
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
          # Clean up variants that are no longer possible after option deletion
          if @item.track_variants?
            cleanup_variants_after_option_deletion
          end
          
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
      
      # Automatically expand variants when a new option is added
      def expand_variants_for_new_option(new_option)
        return unless @item.track_variants?
        
        Rails.logger.info "Auto-expanding variants for new option '#{new_option.name}' in item #{@item.id}"
        
        # Get current variants before expansion
        existing_variants = @item.item_variants.to_a
        existing_variant_keys = existing_variants.map(&:variant_key)
        
        # Generate all possible combinations (including new ones)
        all_combinations = @item.generate_all_variant_combinations
        
        # Create only the new variants (preserve existing ones)
        new_variants_created = 0
        
        all_combinations.each do |combination|
          variant_key = @item.generate_variant_key(combination[:selected_options])
          
          # Skip if this variant already exists
          next if existing_variant_keys.include?(variant_key)
          
          # Create the new variant
          variant_name = @item.generate_variant_name(combination[:selected_options])
          
          variant = @item.item_variants.create!(
            variant_key: variant_key,
            variant_name: variant_name,
            stock_quantity: 0,
            damaged_quantity: 0,
            low_stock_threshold: 5, # Default threshold
            active: true
          )
          
          new_variants_created += 1
          Rails.logger.info "Created new variant: #{variant_name} (ID: #{variant.id})"
        end
        
        Rails.logger.info "Auto-expansion complete: #{new_variants_created} new variants created"
        
      rescue StandardError => e
        Rails.logger.error "Error auto-expanding variants for item #{@item.id}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Don't raise - let the option creation succeed even if variant expansion fails
      end
      
      # Clean up variants that are no longer possible after option deletion
      def cleanup_variants_after_option_deletion
        Rails.logger.info "Cleaning up variants after option deletion for item #{@item.id}"
        
        # Get all valid combinations after the option deletion
        valid_combinations = @item.generate_all_variant_combinations
        valid_variant_keys = valid_combinations.map { |combo| @item.generate_variant_key(combo[:selected_options]) }
        
        # Find variants that are no longer valid
        invalid_variants = @item.item_variants.where.not(variant_key: valid_variant_keys)
        
        if invalid_variants.any?
          deleted_count = invalid_variants.count
          variant_names = invalid_variants.pluck(:variant_name)
          
          # Delete invalid variants
          invalid_variants.destroy_all
          
          Rails.logger.info "Deleted #{deleted_count} invalid variants: #{variant_names.join(', ')}"
        else
          Rails.logger.info "No invalid variants found after option deletion"
        end
        
      rescue StandardError => e
        Rails.logger.error "Error cleaning up variants for item #{@item.id}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Don't raise - let the option deletion succeed even if variant cleanup fails
      end
      
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

      # Create audit trail for option inventory setup
      def create_option_inventory_audit(option, action)
        return unless option.inventory_tracking_enabled? && option.stock_quantity.present? && option.stock_quantity > 0

        # Create audit record for initial option inventory setup
        # For new options, previous quantity is 0
        Wholesale::OptionStockAudit.create!(
          wholesale_option: option,
          audit_type: 'stock_update',
          quantity_change: option.stock_quantity,
          previous_quantity: 0,
          new_quantity: option.stock_quantity,
          reason: "Initial option inventory setup: #{option.stock_quantity} units",
          user: current_user
        )
        
        Rails.logger.info "Created initial option inventory audit for option #{option.id} (#{option.name}): #{option.stock_quantity} units by user #{current_user.id}"
      rescue => e
        Rails.logger.error "Failed to create option inventory audit for option #{option.id}: #{e.message}"
        # Don't fail the option creation if audit fails
      end

      # Create audit trail for option inventory changes
      def create_option_inventory_update_audit(option, old_stock_quantity)
        return unless option.inventory_tracking_enabled?

        # Check if this is the first time stock is being set (tracking was enabled but no stock was set before)
        if old_stock_quantity.nil? && option.stock_quantity.present? && option.stock_quantity > 0
          # First time setting stock after enabling tracking
          Wholesale::OptionStockAudit.create!(
            wholesale_option: option,
            audit_type: 'stock_update',
            quantity_change: option.stock_quantity,
            previous_quantity: 0,
            new_quantity: option.stock_quantity,
            reason: "Initial stock setup after enabling tracking: #{option.stock_quantity} units",
            user: current_user
          )
          
          Rails.logger.info "Created initial stock setup audit for option #{option.id} (#{option.name}): #{option.stock_quantity} units by user #{current_user.id}"
        elsif old_stock_quantity.present? && option.stock_quantity.present? && old_stock_quantity != option.stock_quantity
          # Stock quantity changed
          quantity_change = option.stock_quantity - old_stock_quantity
          
          if quantity_change > 0
            # Stock increased
            Wholesale::OptionStockAudit.create!(
              wholesale_option: option,
              audit_type: 'stock_update',
              quantity_change: quantity_change,
              previous_quantity: old_stock_quantity,
              new_quantity: option.stock_quantity,
              reason: "Stock adjusted from #{old_stock_quantity} to #{option.stock_quantity} (+#{quantity_change})",
              user: current_user
            )
          elsif quantity_change < 0
            # Stock decreased
            Wholesale::OptionStockAudit.create!(
              wholesale_option: option,
              audit_type: 'stock_update',
              quantity_change: quantity_change,
              previous_quantity: old_stock_quantity,
              new_quantity: option.stock_quantity,
              reason: "Stock adjusted from #{old_stock_quantity} to #{option.stock_quantity} (#{quantity_change})",
              user: current_user
            )
          end
          
          Rails.logger.info "Created stock adjustment audit for option #{option.id} (#{option.name}): #{quantity_change} units by user #{current_user.id}"
        end
      rescue => e
        Rails.logger.error "Failed to create option inventory update audit for option #{option.id}: #{e.message}"
        # Don't fail the option update if audit fails
      end
    end
  end
end