# app/controllers/wholesale/admin/items_controller.rb

module Wholesale
  module Admin
    class ItemsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_fundraiser, only: [:index, :show, :create, :update, :destroy, :toggle_active, :bulk_update], if: :nested_route?
      before_action :set_item, only: [:show, :update, :destroy, :toggle_active, :set_primary_image]
      before_action :set_restaurant_context
      
      # GET /wholesale/admin/items
      # GET /wholesale/admin/fundraisers/:fundraiser_id/items
      def index
        items = Wholesale::Item.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .includes(:fundraiser, :item_images, option_groups: :options)
        
        # Apply fundraiser scoping if present
        if @fundraiser
          # Nested route: scope to specific fundraiser
          items = items.where(fundraiser_id: @fundraiser.id)
        elsif params[:fundraiser_id].present?
          # Parameter-based filtering for backward compatibility
          items = items.where(fundraiser_id: params[:fundraiser_id])
        end
        
        # Add computed fields
        items_with_stats = items.map do |item|
          item_with_computed_fields(item)
        end
        
        render_success(items: items_with_stats)
      end
      
      # GET /wholesale/admin/items/:id
      def show
        render_success(item: item_with_computed_fields(@item))
      end
      
      # POST /wholesale/admin/items
      # POST /wholesale/admin/fundraisers/:fundraiser_id/items
      def create
        # Use @fundraiser if set (nested route), otherwise verify from params
        fundraiser = @fundraiser
        
        if fundraiser.nil?
          # Flat route: verify fundraiser belongs to current restaurant
          fundraiser = Wholesale::Fundraiser.where(restaurant: current_restaurant)
            .find_by(id: item_params[:fundraiser_id])
          
          unless fundraiser
            render_error('Fundraiser not found or not accessible')
            return
          end
        end
        
        # Ensure fundraiser_id is set correctly for nested routes
        create_params = item_params.except(:images)
        create_params[:fundraiser_id] = fundraiser.id
        
        item = Wholesale::Item.new(create_params)
        
        if item.save
          # Process legacy variant options and convert to option groups
          process_legacy_options(item, create_params[:options]) if create_params[:options].present?
          
          # Process image uploads if present
          process_image_uploads(item, item_params[:images]) if item_params[:images].present?
          
          # Create audit trail for initial inventory setup
          create_initial_inventory_audit(item, create_params)
          
          # Reload to include any created images and option groups
          item.reload
          render_success(item: item_with_computed_fields(item), message: 'Item created successfully!', status: :created)
        else
          render_error('Failed to create item', errors: item.errors.full_messages)
        end
      end
      
      # PATCH/PUT /wholesale/admin/items/:id
      def update
        # Separate image operations from item updates
        update_params = item_params.except(:images, :delete_image_ids)
        
        # Track changes for audit trail
        old_track_inventory = @item.track_inventory
        old_stock_quantity = @item.stock_quantity
        
        if @item.update(update_params)
          # Process legacy variant options and convert to option groups
          process_legacy_options(@item, update_params[:options]) if update_params[:options].present?
          
          # Process image deletions if present
          process_image_deletions(@item, item_params[:delete_image_ids]) if item_params[:delete_image_ids].present?
          
          # Process image uploads if present
          process_image_uploads(@item, item_params[:images]) if item_params[:images].present?
          
          # Create audit trail for inventory setup changes
          create_inventory_update_audit(@item, old_track_inventory, old_stock_quantity, update_params)
          
          # Reload to include any image changes and option groups
          @item.reload
          render_success(item: item_with_computed_fields(@item), message: 'Item updated successfully!')
        else
          render_error('Failed to update item', errors: @item.errors.full_messages)
        end
      end
      
      # DELETE /wholesale/admin/items/:id
      def destroy
        if @item.destroy
          render_success(message: 'Item deleted successfully!')
        else
          render_error('Failed to delete item', errors: @item.errors.full_messages)
        end
      end
      
      # PATCH /wholesale/admin/items/:id/toggle_active
      def toggle_active
        @item.active = !@item.active
        
        if @item.save
          render_success(item: @item, message: "Item #{@item.active? ? 'activated' : 'deactivated'} successfully!")
        else
          render_error('Failed to toggle item status', errors: @item.errors.full_messages)
        end
      end
      
      # POST /wholesale/admin/items/bulk_update
      def bulk_update
        # TODO: Implement bulk update functionality
        render_success(message: 'Bulk update functionality coming soon')
      end
      
      # PATCH /wholesale/admin/items/:id/set_primary_image
      def set_primary_image
        image_id = params[:image_id]
        
        unless image_id.present?
          render_error('Image ID is required')
          return
        end
        
        # Find the image and ensure it belongs to this item
        image = @item.item_images.find_by(id: image_id)
        
        unless image
          render_error('Image not found')
          return
        end
        
        begin
          image.make_primary!
          @item.reload
          render_success(
            item: item_with_computed_fields(@item),
            message: 'Primary image updated successfully!'
          )
        rescue => e
          render_error("Failed to update primary image: #{e.message}")
        end
      end
      
      private
      
      def set_item
        query = Wholesale::Item.joins(:fundraiser)
          .where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
          .includes(:fundraiser, :item_images, option_groups: :options)
        
        # Additional scoping for nested routes
        if @fundraiser
          query = query.where(fundraiser_id: @fundraiser.id)
        end
        
        @item = query.find_by(id: params[:id])
        render_not_found('Item not found') unless @item
      end
      
      def item_params
        permitted_params = params.require(:item).permit(
          :fundraiser_id, :name, :description, :price, :price_cents, :sku, :image_url,
          :stock_quantity, :low_stock_threshold, :track_inventory, :allow_sale_with_no_stock, :active,
          :position, :sort_order, :options, :custom_variant_skus,
          images: [],
          delete_image_ids: []
        )
        
        # Convert price to price_cents if price is provided instead of price_cents
        if permitted_params[:price].present? && permitted_params[:price_cents].blank?
          permitted_params[:price_cents] = (permitted_params[:price].to_f * 100).round
          permitted_params.delete(:price)
        end
        
        # Convert string values to proper types (FormData sends everything as strings)
        # Integer conversions
        [:fundraiser_id, :position, :sort_order, :stock_quantity, :low_stock_threshold, :price_cents].each do |field|
          if permitted_params[field].present?
            permitted_params[field] = permitted_params[field].to_i
          end
        end
        
        # Boolean conversions  
        [:track_inventory, :allow_sale_with_no_stock, :active].each do |field|
          if permitted_params[field].present?
            permitted_params[field] = permitted_params[field].to_s.downcase.in?(['true', '1', 'yes', 'on'])
          end
        end
        
        # Parse options JSON if it's a string
        if permitted_params[:options].is_a?(String)
          begin
            permitted_params[:options] = JSON.parse(permitted_params[:options])
          rescue JSON::ParserError
            permitted_params[:options] = {}
          end
        end
        
        # Clear inventory fields when track_inventory is false (model validation requirement)
        unless permitted_params[:track_inventory]
          permitted_params[:stock_quantity] = nil
          permitted_params[:low_stock_threshold] = nil
        end
        
        permitted_params
      end
      
      # Convert legacy variant options to option groups
      def process_legacy_options(item, options_data)
        return unless options_data.is_a?(Hash)
        
        Rails.logger.info "Processing legacy options for item #{item.id}: #{options_data.inspect}"
        
        # Extract size and color options from the legacy format
        size_options = options_data['size_options'] || []
        color_options = options_data['color_options'] || []
        
        # Create Size option group if size options exist
        if size_options.any?
          size_group = item.option_groups.create!(
            name: 'Size',
            min_select: 1,
            max_select: 1,
            required: true,
            position: 1,
            enable_inventory_tracking: false
          )
          
          size_options.each_with_index do |size, index|
            size_group.options.create!(
              name: size,
              additional_price: 0.0,
              available: true,
              position: index + 1,
              stock_quantity: nil,
              damaged_quantity: 0,
              low_stock_threshold: nil,
              total_ordered: 0,
              total_revenue: 0.0
            )
          end
          
          Rails.logger.info "Created Size option group with #{size_options.length} options"
        end
        
        # Create Color option group if color options exist
        if color_options.any?
          color_group = item.option_groups.create!(
            name: 'Color',
            min_select: 1,
            max_select: 1,
            required: true,
            position: 2,
            enable_inventory_tracking: false
          )
          
          color_options.each_with_index do |color, index|
            color_group.options.create!(
              name: color,
              additional_price: 0.0,
              available: true,
              position: index + 1,
              stock_quantity: nil,
              damaged_quantity: 0,
              low_stock_threshold: nil,
              total_ordered: 0,
              total_revenue: 0.0
            )
          end
          
          Rails.logger.info "Created Color option group with #{color_options.length} options"
        end
        
        # Clear the legacy options field since we've converted to option groups
        item.update_column(:options, {})
        
      rescue StandardError => e
        Rails.logger.error "Error processing legacy options for item #{item.id}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        # Don't raise the error - let the item creation succeed even if option group creation fails
      end

      
      def process_image_uploads(item, image_files)
        return unless image_files.is_a?(Array)
        
        # Get the current maximum position and check if there's already a primary image
        max_position = item.item_images.maximum(:position) || 0
        has_primary = item.item_images.exists?(primary: true)
        
        image_files.each_with_index do |file, index|
          next unless file.present? && file.respond_to?(:original_filename)
          
          begin
            # Generate unique filename
            ext = File.extname(file.original_filename)
            timestamp = Time.now.to_i
            new_filename = "wholesale_item_#{item.id}_#{timestamp}_#{index + 1}#{ext}"
            
            # Upload to S3
            public_url = S3Uploader.upload(file, new_filename)
            
            # Calculate position and primary status
            new_position = max_position + index + 1
            is_primary = !has_primary && index == 0 # Only first image is primary if no existing primary
            
            # Create ItemImage record
            item.item_images.create!(
              image_url: public_url,
              position: new_position,
              primary: is_primary,
              alt_text: "#{item.name} - Image #{new_position}"
            )
            
          rescue => e
            Rails.logger.error "[WholesaleItemsController] Image upload failed for item #{item.id}, image #{index + 1}: #{e.message}"
            Rails.logger.error "[WholesaleItemsController] Backtrace: #{e.backtrace.join("\n")}"
            # Continue processing other images
          end
        end
      end
      
      def process_image_deletions(item, image_ids)
        return unless image_ids.is_a?(Array)
        
        image_ids.each do |image_id|
          next unless image_id.present?
          
          begin
            # Find the image that belongs to this item
            image = item.item_images.find_by(id: image_id)
            next unless image
            
            Rails.logger.info "[WholesaleItemsController] Deleting image #{image.id} for item #{item.id}"
            
            # Delete the image record (S3 cleanup could be added here if needed)
            image.destroy!
            
          rescue => e
            Rails.logger.error "[WholesaleItemsController] Image deletion failed for item #{item.id}, image #{image_id}: #{e.message}"
            Rails.logger.error "[WholesaleItemsController] Backtrace: #{e.backtrace.join("\n")}"
            # Continue with other deletions even if one fails
          end
        end
      end

      def item_with_computed_fields(item)
        # Calculate stock status
        stock_status = 'unlimited'
        
        if item.track_inventory && item.stock_quantity.present?
          # Item-level inventory tracking
          if item.stock_quantity <= 0
            stock_status = 'out_of_stock'
          elsif item.low_stock_threshold.present? && item.stock_quantity <= item.low_stock_threshold
            stock_status = 'low_stock'
          else
            stock_status = 'in_stock'
          end
        elsif item.uses_option_level_inventory?
          # Option-level inventory tracking
          effective_qty = item.effective_available_quantity
          if effective_qty.is_a?(Numeric)
            tracking_group = item.option_inventory_tracking_group
            if tracking_group
              # Calculate aggregate low stock threshold
              total_low_threshold = tracking_group.options.active.sum(:low_stock_threshold)
              
              if effective_qty <= 0
                stock_status = 'out_of_stock'
              elsif total_low_threshold > 0 && effective_qty <= total_low_threshold
                stock_status = 'low_stock'
              else
                stock_status = 'in_stock'
              end
            else
              stock_status = 'in_stock' # Fallback if no tracking group
            end
          end
        end
        
        # Calculate performance metrics from order items
        # Note: All orders count as revenue since orders can only be created after payment
        all_order_items = item.order_items.joins(:order)
        
        total_ordered = all_order_items.sum(:quantity)
        total_revenue_cents = all_order_items.sum('quantity * price_cents')
        
        item.attributes.merge(
          'fundraiser_name' => item.fundraiser&.name,
          'price' => item.price_cents / 100.0,
          'stock_status' => stock_status,
          'in_stock' => !item.track_inventory || (item.stock_quantity.present? && item.stock_quantity > 0),
          'total_ordered' => total_ordered,
          'total_revenue' => total_revenue_cents / 100.0,
          'images_count' => item.item_images.count,
          'item_images' => item.item_images.order(:position).map do |img|
            {
              id: img.id,
              image_url: img.image_url,
              alt_text: img.alt_text,
              position: img.position,
              primary: img.primary
            }
          end,
          'variants' => item.variants.map do |variant|
            {
              id: variant.id,
              sku: variant.sku,
              size: variant.size,
              color: variant.color,
              display_name: variant.display_name,
              price_adjustment: variant.price_adjustment,
              final_price: variant.final_price,
              stock_quantity: variant.stock_quantity,
              low_stock_threshold: variant.low_stock_threshold,
              total_ordered: variant.total_ordered,
              total_revenue: variant.total_revenue,
              active: variant.active,
              can_purchase: variant.can_purchase?
            }
          end,
          'has_variants' => item.has_variants?,
          'variant_count' => item.variants.active.count,
          
          # Option Groups (new system)
          'option_groups' => item.option_groups.includes(:options).order(:position).map do |group|
            {
              id: group.id,
              name: group.name,
              min_select: group.min_select,
              max_select: group.max_select,
              required: group.required,
              position: group.position,
              enable_inventory_tracking: group.enable_inventory_tracking,
              has_available_options: group.has_available_options?,
              required_but_unavailable: group.required_but_unavailable?,
              options: group.options.order(:position).map do |option|
                {
                  id: option.id,
                  name: option.name,
                  additional_price: option.additional_price.to_f,
                  available: option.available,
                  position: option.position,
                  total_ordered: option.total_ordered,
                  total_revenue: option.total_revenue.to_f,
                  stock_quantity: option.stock_quantity,
                  damaged_quantity: option.damaged_quantity,
                  low_stock_threshold: option.low_stock_threshold,
                  inventory_tracking_enabled: option.inventory_tracking_enabled?,
                  available_stock: option.available_stock,
                  in_stock: option.in_stock?,
                  out_of_stock: option.out_of_stock?,
                  low_stock: option.low_stock?,
                  final_price: option.final_price,
                  display_name: option.display_name
                }
              end
            }
          end,
          'has_options' => item.has_options?,
          'option_groups_count' => item.option_groups.count,
          'orders_sold' => total_ordered, # Alias for backward compatibility
          'revenue_generated_cents' => total_revenue_cents, # Alias for backward compatibility
          
          # Inventory tracking fields
          'uses_option_level_inventory' => item.uses_option_level_inventory?,
          'has_option_inventory_tracking' => item.has_option_inventory_tracking?,
          'effective_available_quantity' => item.effective_available_quantity,
          'available_quantity' => item.available_quantity,
          'damaged_quantity' => item.damaged_quantity
        )
      end

      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end

      def set_fundraiser
        @fundraiser = Wholesale::Fundraiser.where(restaurant: current_restaurant)
          .find_by(id: params[:fundraiser_id])
        render_not_found('Fundraiser not found') unless @fundraiser
      end

      def nested_route?
        params[:fundraiser_id].present?
      end

      # Create audit trail for initial inventory setup during item creation
      def create_initial_inventory_audit(item, create_params)
        return unless create_params[:track_inventory] && create_params[:stock_quantity].present? && create_params[:stock_quantity] > 0

        # Create audit record for initial item-level inventory setup
        # For new items, previous quantity is 0
        Wholesale::ItemStockAudit.create!(
          wholesale_item: item,
          audit_type: 'stock_update',
          quantity_change: create_params[:stock_quantity],
          previous_quantity: 0,
          new_quantity: create_params[:stock_quantity],
          reason: "Initial inventory setup: #{create_params[:stock_quantity]} units",
          user: current_user
        )
        
        Rails.logger.info "Created initial inventory audit for item #{item.id}: #{create_params[:stock_quantity]} units by user #{current_user.id}"
      rescue => e
        Rails.logger.error "Failed to create initial inventory audit for item #{item.id}: #{e.message}"
        # Don't fail the item creation if audit fails
      end

      # Create audit trail for inventory setup changes during item updates
      def create_inventory_update_audit(item, old_track_inventory, old_stock_quantity, update_params)
        # Check if inventory tracking was just enabled
        if !old_track_inventory && update_params[:track_inventory] && update_params[:stock_quantity].present? && update_params[:stock_quantity] > 0
          # Inventory tracking was just enabled with initial stock
          # Create audit record with explicit previous quantity
          Wholesale::ItemStockAudit.create!(
            wholesale_item: item,
            audit_type: 'stock_update',
            quantity_change: update_params[:stock_quantity] - (old_stock_quantity || 0),
            previous_quantity: old_stock_quantity || 0,
            new_quantity: update_params[:stock_quantity],
            reason: "Inventory tracking enabled with initial stock: #{update_params[:stock_quantity]} units",
            user: current_user
          )
          
          Rails.logger.info "Created inventory tracking enabled audit for item #{item.id}: #{update_params[:stock_quantity]} units by user #{current_user.id}"
        elsif old_track_inventory && update_params[:track_inventory] && update_params[:stock_quantity].present?
          # Inventory tracking was already enabled, check if stock quantity changed
          if old_stock_quantity != update_params[:stock_quantity]
            quantity_change = update_params[:stock_quantity] - (old_stock_quantity || 0)
            
            if quantity_change > 0
              # Stock increased
              Wholesale::ItemStockAudit.create_stock_record(
                item,
                quantity_change,
                'manual_adjustment',
                "Stock adjusted from #{old_stock_quantity || 0} to #{update_params[:stock_quantity]} (+#{quantity_change})",
                current_user
              )
            elsif quantity_change < 0
              # Stock decreased
              Wholesale::ItemStockAudit.create_stock_record(
                item,
                quantity_change,
                'manual_adjustment',
                "Stock adjusted from #{old_stock_quantity || 0} to #{update_params[:stock_quantity]} (#{quantity_change})",
                current_user
              )
            end
            
            Rails.logger.info "Created stock adjustment audit for item #{item.id}: #{quantity_change} units by user #{current_user.id}"
          end
        end
      rescue => e
        Rails.logger.error "Failed to create inventory update audit for item #{item.id}: #{e.message}"
        # Don't fail the item update if audit fails
      end
    end
  end
end