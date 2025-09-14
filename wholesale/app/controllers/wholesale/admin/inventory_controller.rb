# app/controllers/wholesale/admin/inventory_controller.rb

module Wholesale
  module Admin
    class InventoryController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_item, only: [:show, :update_item_stock, :mark_damaged, :restock, :enable_tracking, :disable_tracking]
      before_action :set_option, only: [:update_option_stock, :mark_option_damaged, :restock_option]
      before_action :set_variant, only: [:update_variant_stock, :mark_variant_damaged, :restock_variant, :toggle_variant_active]
      
      # GET /wholesale/admin/inventory
      # Overview of all inventory across fundraisers
      def index
        # Get all items with inventory tracking enabled
        items_with_tracking = Wholesale::Item.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .where(track_inventory: true)
          .includes(:fundraiser, :item_stock_audits)
          .order(:name)
        
        # Get all items with option-level tracking
        items_with_option_tracking = Wholesale::Item.joins(:fundraiser, option_groups: :options)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .where(wholesale_option_groups: { enable_inventory_tracking: true })
          .includes(:fundraiser, option_groups: :options)
          .distinct
          .order(:name)
        
        # Combine and format data
        inventory_summary = {
          item_level_tracking: items_with_tracking.map { |item| item_inventory_summary(item) },
          option_level_tracking: items_with_option_tracking.map { |item| option_inventory_summary(item) },
          totals: calculate_inventory_totals(items_with_tracking, items_with_option_tracking)
        }
        
        render_success(inventory_summary)
      end
      
      # GET /wholesale/admin/inventory/items/:id
      # Detailed inventory view for a specific item
      def show
        inventory_data = {
          item: detailed_item_inventory(@item),
          audit_trail: recent_audit_trail(@item),
          recommendations: inventory_recommendations(@item)
        }
        
        render_success(inventory_data)
      end
      
      # POST /wholesale/admin/inventory/items/:id/update_stock
      # Update item-level stock quantity
      def update_item_stock
        unless @item.track_inventory?
          return render_error('Item does not have inventory tracking enabled')
        end
        
        new_quantity = params[:quantity].to_i
        reason = params[:reason] || 'Manual adjustment'
        notes = params[:notes]
        
        if @item.update_stock_quantity(new_quantity, 'manual_adjustment', notes, current_user)
          render_success(
            item: detailed_item_inventory(@item),
            message: "Stock updated to #{new_quantity} units"
          )
        else
          render_error('Failed to update stock quantity')
        end
      end
      
      # POST /wholesale/admin/inventory/items/:id/mark_damaged
      # Mark items as damaged
      def mark_damaged
        unless @item.track_inventory?
          return render_error('Item does not have inventory tracking enabled')
        end
        
        quantity = params[:quantity].to_i
        reason = params[:reason] || 'Damaged items'
        
        if @item.mark_as_damaged(quantity, reason, current_user)
          render_success(
            item: detailed_item_inventory(@item),
            message: "Marked #{quantity} items as damaged"
          )
        else
          render_error('Failed to mark items as damaged')
        end
      end
      
      # POST /wholesale/admin/inventory/items/:id/restock
      # Add stock to item
      def restock
        unless @item.track_inventory?
          return render_error('Item does not have inventory tracking enabled')
        end
        
        quantity = params[:quantity].to_i
        notes = params[:notes] || 'Restocked'
        
        if @item.restock!(quantity, notes: notes, user: current_user)
          render_success(
            item: detailed_item_inventory(@item),
            message: "Added #{quantity} items to stock"
          )
        else
          render_error('Failed to restock item')
        end
      end
      
      # POST /wholesale/admin/inventory/items/:id/enable_tracking
      # Enable inventory tracking for an item
      def enable_tracking
        if @item.update(track_inventory: true, stock_quantity: 0, stock_status: 'in_stock')
          render_success(
            item: detailed_item_inventory(@item),
            message: 'Inventory tracking enabled'
          )
        else
          render_error('Failed to enable inventory tracking', errors: @item.errors.full_messages)
        end
      end
      
      # POST /wholesale/admin/inventory/items/:id/disable_tracking
      # Disable inventory tracking for an item
      def disable_tracking
        if @item.update(track_inventory: false, stock_quantity: nil, low_stock_threshold: nil, stock_status: 'unlimited')
          render_success(
            item: detailed_item_inventory(@item),
            message: 'Inventory tracking disabled'
          )
        else
          render_error('Failed to disable inventory tracking', errors: @item.errors.full_messages)
        end
      end
      
      # POST /wholesale/admin/inventory/options/:id/update_stock
      # Update option-level stock quantity
      def update_option_stock
        unless @option.inventory_tracking_enabled?
          return render_error('Option does not have inventory tracking enabled')
        end
        
        new_quantity = params[:quantity].to_i
        notes = params[:notes]
        
        if @option.update_stock_quantity(new_quantity, 'manual_adjustment', notes, current_user)
          render_success(
            option: detailed_option_inventory(@option),
            message: "Stock updated to #{new_quantity} units for #{@option.name}"
          )
        else
          render_error('Failed to update option stock quantity')
        end
      end
      
      # POST /wholesale/admin/inventory/options/:id/mark_damaged
      # Mark option items as damaged
      def mark_option_damaged
        unless @option.inventory_tracking_enabled?
          return render_error('Option does not have inventory tracking enabled')
        end
        
        quantity = params[:quantity].to_i
        reason = params[:reason] || 'Damaged items'
        
        if @option.mark_as_damaged(quantity, reason, current_user)
          render_success(
            option: detailed_option_inventory(@option),
            message: "Marked #{quantity} #{@option.name} items as damaged"
          )
        else
          render_error('Failed to mark option items as damaged')
        end
      end
      
      # POST /wholesale/admin/inventory/options/:id/restock
      # Add stock to option
      def restock_option
        unless @option.inventory_tracking_enabled?
          return render_error('Option does not have inventory tracking enabled')
        end
        
        quantity = params[:quantity].to_i
        notes = params[:notes] || 'Restocked'
        
        if @option.restock!(quantity, notes: notes, user: current_user)
          render_success(
            option: detailed_option_inventory(@option),
            message: "Added #{quantity} #{@option.name} items to stock"
          )
        else
          render_error('Failed to restock option')
        end
      end
      
      # GET /wholesale/admin/inventory/audit_trail
      # Get comprehensive audit trail
      def audit_trail
        # Get recent audit records
        item_audits = Wholesale::ItemStockAudit.joins(wholesale_item: :fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .includes(:wholesale_item, :user, :order)
          .recent
          .limit(50)
        
        option_audits = Wholesale::OptionStockAudit.joins(wholesale_option: { option_group: { wholesale_item: :fundraiser } })
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .includes(:wholesale_option, :user, :order)
          .recent
          .limit(50)
        
        variant_audits = Wholesale::VariantStockAudit.joins(wholesale_item_variant: { wholesale_item: :fundraiser })
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .includes(:wholesale_item_variant, :user, :order)
          .recent
          .limit(50)
        
        # Combine and sort by timestamp
        all_audits = (item_audits.to_a + option_audits.to_a + variant_audits.to_a).sort_by(&:created_at).reverse
        
        audit_data = all_audits.map do |audit|
          format_audit_record(audit)
        end
        
        render_success(audit_trail: audit_data)
      end
      
      # NEW: Variant-level inventory management methods
      
      # POST /wholesale/admin/inventory/variants/:id/update_stock
      # Update stock quantity for a specific variant
      def update_variant_stock
        new_quantity = params[:quantity].to_i
        reason = params[:reason] || 'admin_adjustment'
        notes = params[:notes] || "Stock updated by admin"
        
        if new_quantity < 0
          return render_error("Stock quantity cannot be negative")
        end
        
        if @variant.update_stock_quantity(new_quantity, reason, notes, current_user)
          render_success(
            variant: variant_inventory_summary(@variant),
            message: "Stock updated successfully"
          )
        else
          render_error("Failed to update stock")
        end
      end
      
      # POST /wholesale/admin/inventory/variants/:id/mark_damaged
      # Mark quantity as damaged for a specific variant
      def mark_variant_damaged
        damaged_quantity = params[:quantity].to_i
        reason = params[:reason] || 'damaged_goods'
        notes = params[:notes] || "Marked as damaged by admin"
        
        if damaged_quantity <= 0
          return render_error("Damaged quantity must be greater than 0")
        end
        
        if @variant.mark_damaged!(damaged_quantity, reason, notes, current_user)
          render_success(
            variant: variant_inventory_summary(@variant),
            message: "Damaged quantity updated successfully"
          )
        else
          render_error("Failed to mark as damaged")
        end
      end
      
      # POST /wholesale/admin/inventory/variants/:id/restock
      # Add stock to a specific variant
      def restock_variant
        restock_quantity = params[:quantity].to_i
        reason = params[:reason] || 'restock'
        notes = params[:notes] || "Restocked by admin"
        
        if restock_quantity <= 0
          return render_error("Restock quantity must be greater than 0")
        end
        
        if @variant.restock!(restock_quantity, reason: reason, notes: notes, user: current_user)
          render_success(
            variant: variant_inventory_summary(@variant),
            message: "Variant restocked successfully"
          )
        else
          render_error("Failed to restock")
        end
      end
      
      # POST /wholesale/admin/inventory/variants/:id/toggle_active
      # Toggle active status for a specific variant
      def toggle_variant_active
        if @variant.toggle_active!(user: current_user)
          render_success(
            variant: variant_inventory_summary(@variant),
            message: "Variant status updated successfully"
          )
        else
          render_error("Failed to update status")
        end
      end
      
      private
      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end
      
      def set_item
        @item = Wholesale::Item.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error('Item not found')
      end
      
      def set_option
        @option = Wholesale::Option.joins(option_group: { wholesale_item: :fundraiser })
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error('Option not found')
      end
      
      def set_variant
        @variant = Wholesale::ItemVariant.joins(wholesale_item: :fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error('Variant not found')
      end
      
      def item_inventory_summary(item)
        {
          id: item.id,
          name: item.name,
          fundraiser: item.fundraiser.name,
          track_inventory: item.track_inventory?,
          stock_quantity: item.stock_quantity,
          damaged_quantity: item.damaged_quantity,
          available_quantity: item.available_quantity,
          low_stock_threshold: item.low_stock_threshold,
          stock_status: item.stock_status,
          last_restocked_at: item.last_restocked_at,
          needs_attention: item.low_stock? || item.out_of_stock?
        }
      end
      
      def option_inventory_summary(item)
        tracking_group = item.option_inventory_tracking_group
        return nil unless tracking_group
        
        {
          id: item.id,
          name: item.name,
          fundraiser: item.fundraiser.name,
          option_group: tracking_group.name,
          total_stock: tracking_group.total_option_stock,
          available_stock: tracking_group.available_option_stock,
          has_stock: tracking_group.has_option_stock?,
          options: tracking_group.options.active.map do |option|
            {
              id: option.id,
              name: option.name,
              stock_quantity: option.stock_quantity,
              damaged_quantity: option.damaged_quantity,
              available_stock: option.available_stock,
              in_stock: option.in_stock?,
              out_of_stock: option.out_of_stock?,
              low_stock: option.low_stock?
            }
          end,
          needs_attention: tracking_group.out_of_stock_options.any? || tracking_group.low_stock_options.any?
        }
      end
      
      def variant_inventory_summary(variant)
        {
          id: variant.id,
          variant_key: variant.variant_key,
          variant_name: variant.variant_name,
          item: {
            id: variant.wholesale_item.id,
            name: variant.wholesale_item.name,
            fundraiser: variant.wholesale_item.fundraiser.name
          },
          stock_quantity: variant.stock_quantity,
          damaged_quantity: variant.damaged_quantity,
          available_stock: variant.available_stock,
          low_stock_threshold: variant.low_stock_threshold,
          active: variant.active?,
          stock_status: variant.stock_status,
          is_low_stock: variant.low_stock?,
          is_out_of_stock: variant.out_of_stock?,
          needs_attention: variant.low_stock? || variant.out_of_stock? || !variant.active?,
          last_updated: variant.updated_at
        }
      end
      
      def detailed_item_inventory(item)
        {
          id: item.id,
          name: item.name,
          sku: item.sku,
          fundraiser: {
            id: item.fundraiser.id,
            name: item.fundraiser.name
          },
          track_inventory: item.track_inventory?,
          uses_option_level_inventory: item.uses_option_level_inventory?,
          stock_quantity: item.stock_quantity,
          damaged_quantity: item.damaged_quantity,
          available_quantity: item.available_quantity,
          effective_available_quantity: item.effective_available_quantity,
          low_stock_threshold: item.low_stock_threshold,
          actual_low_stock_threshold: item.actual_low_stock_threshold,
          stock_status: item.stock_status,
          in_stock: item.in_stock?,
          out_of_stock: item.out_of_stock?,
          low_stock: item.low_stock?,
          effectively_out_of_stock: item.effectively_out_of_stock?,
          last_restocked_at: item.last_restocked_at,
          option_groups: item.option_groups.includes(:options).map do |group|
            {
              id: group.id,
              name: group.name,
              inventory_tracking_enabled: group.inventory_tracking_enabled?,
              total_option_stock: group.total_option_stock,
              available_option_stock: group.available_option_stock,
              has_option_stock: group.has_option_stock?,
              options: group.options.active.map do |option|
                detailed_option_inventory(option)
              end
            }
          end
        }
      end
      
      def detailed_option_inventory(option)
        {
          id: option.id,
          name: option.name,
          inventory_tracking_enabled: option.inventory_tracking_enabled?,
          stock_quantity: option.stock_quantity,
          damaged_quantity: option.damaged_quantity,
          available_stock: option.available_stock,
          low_stock_threshold: option.low_stock_threshold,
          actual_low_stock_threshold: option.actual_low_stock_threshold,
          in_stock: option.in_stock?,
          out_of_stock: option.out_of_stock?,
          low_stock: option.low_stock?,
          total_ordered: option.total_ordered,
          total_revenue: option.total_revenue
        }
      end
      
      def recent_audit_trail(item)
        # Get recent audits for this item
        item_audits = item.item_stock_audits.includes(:user, :order).recent.limit(20)
        
        # Get recent audits for options if using option-level inventory
        option_audits = []
        if item.uses_option_level_inventory?
          option_audits = Wholesale::OptionStockAudit.joins(wholesale_option: :option_group)
            .where(wholesale_option_groups: { wholesale_item_id: item.id })
            .includes(:wholesale_option, :user, :order)
            .recent
            .limit(20)
        end
        
        # Get recent audits for variants if using variant-level inventory
        variant_audits = []
        if item.track_variants?
          variant_audits = Wholesale::VariantStockAudit.joins(:wholesale_item_variant)
            .where(wholesale_item_variants: { wholesale_item_id: item.id })
            .includes(:wholesale_item_variant, :user, :order)
            .recent
            .limit(20)
        end
        
        # Combine and sort all audit types
        all_audits = (item_audits.to_a + option_audits.to_a + variant_audits.to_a).sort_by(&:created_at).reverse
        
        all_audits.map { |audit| format_audit_record(audit) }
      end
      
      def format_user_info(audit)
        # For order-related audits, show customer info instead of system user
        # Check if this audit is related to an order (has order AND reason mentions order)
        if audit.order && (audit.reason&.include?('Order placed') || audit.reason&.include?('Order cancelled'))
          {
            type: 'customer',
            name: audit.order.customer_name,
            email: audit.order.customer_email
          }
        elsif audit.user
          {
            type: 'admin',
            id: audit.user.id,
            name: "#{audit.user.first_name} #{audit.user.last_name}".strip,
            email: audit.user.email
          }
        else
          {
            type: 'system',
            name: 'System',
            email: nil
          }
        end
      end
      
      def format_audit_record(audit)
        base_data = {
          id: audit.id,
          audit_type: audit.audit_type,
          quantity_change: audit.quantity_change,
          previous_quantity: audit.previous_quantity,
          new_quantity: audit.new_quantity,
          reason: audit.reason,
          created_at: audit.created_at,
          user: format_user_info(audit),
          order: audit.order ? { 
            id: audit.order.id, 
            order_number: audit.order.order_number,
            customer_name: audit.order.customer_name,
            customer_email: audit.order.customer_email
          } : nil
        }
        
        if audit.is_a?(Wholesale::ItemStockAudit)
          base_data.merge({
            type: 'item',
            item: {
              id: audit.wholesale_item.id,
              name: audit.wholesale_item.name
            }
          })
        elsif audit.is_a?(Wholesale::VariantStockAudit)
          base_data.merge({
            type: 'variant',
            variant: {
              id: audit.wholesale_item_variant.id,
              variant_key: audit.wholesale_item_variant.variant_key,
              variant_name: audit.wholesale_item_variant.variant_name
            },
            item: {
              id: audit.wholesale_item_variant.wholesale_item.id,
              name: audit.wholesale_item_variant.wholesale_item.name
            }
          })
        else
          base_data.merge({
            type: 'option',
            option: {
              id: audit.wholesale_option.id,
              name: audit.wholesale_option.name
            },
            item: {
              id: audit.wholesale_option.option_group.wholesale_item.id,
              name: audit.wholesale_option.option_group.wholesale_item.name
            }
          })
        end
      end
      
      def inventory_recommendations(item)
        recommendations = []
        
        if item.track_inventory?
          if item.out_of_stock?
            recommendations << {
              type: 'critical',
              message: 'Item is out of stock',
              action: 'restock'
            }
          elsif item.low_stock?
            recommendations << {
              type: 'warning',
              message: "Item is low stock (#{item.available_quantity} remaining)",
              action: 'restock'
            }
          end
        elsif item.uses_option_level_inventory?
          tracking_group = item.option_inventory_tracking_group
          if tracking_group
            out_of_stock_options = tracking_group.out_of_stock_options
            low_stock_options = tracking_group.low_stock_options
            
            if out_of_stock_options.any?
              recommendations << {
                type: 'critical',
                message: "Options out of stock: #{out_of_stock_options.map(&:name).join(', ')}",
                action: 'restock_options'
              }
            end
            
            if low_stock_options.any?
              recommendations << {
                type: 'warning',
                message: "Options low stock: #{low_stock_options.map(&:name).join(', ')}",
                action: 'restock_options'
              }
            end
          end
        end
        
        recommendations
      end
      
      def calculate_inventory_totals(item_tracking, option_tracking)
        {
          total_items_tracked: item_tracking.count + option_tracking.count,
          items_needing_attention: (
            item_tracking.select { |item| item.low_stock? || item.out_of_stock? }.count +
            option_tracking.select { |item| 
              group = item.option_inventory_tracking_group
              group && (group.out_of_stock_options.any? || group.low_stock_options.any?)
            }.count
          ),
          total_stock_value: calculate_total_stock_value(item_tracking, option_tracking)
        }
      end
      
      def calculate_total_stock_value(item_tracking, option_tracking)
        item_value = item_tracking.sum { |item| (item.available_quantity || 0) * item.price }
        option_value = option_tracking.sum do |item|
          group = item.option_inventory_tracking_group
          next 0 unless group
          group.options.active.sum { |option| (option.available_stock || 0) * item.price }
        end
        item_value + option_value
      end
    end
  end
end
