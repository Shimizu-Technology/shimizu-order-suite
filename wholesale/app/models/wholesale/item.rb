# app/models/wholesale/item.rb

module Wholesale
  class Item < ApplicationRecord
    # Associations
    belongs_to :fundraiser, class_name: 'Wholesale::Fundraiser'
    has_many :item_images, class_name: 'Wholesale::ItemImage', dependent: :destroy
    has_many :order_items, class_name: 'Wholesale::OrderItem', dependent: :restrict_with_error
    has_many :variants, class_name: 'Wholesale::WholesaleItemVariant', foreign_key: 'wholesale_item_id', dependent: :destroy
    has_many :item_variants, class_name: 'Wholesale::ItemVariant', foreign_key: 'wholesale_item_id', dependent: :destroy
    
    # Option Groups (new system)
    has_many :option_groups, class_name: 'Wholesale::OptionGroup', foreign_key: 'wholesale_item_id', dependent: :destroy
    has_many :item_options, through: :option_groups, source: :options, class_name: 'Wholesale::Option'
    
    # Inventory audit trail
    has_many :item_stock_audits, class_name: 'Wholesale::ItemStockAudit', foreign_key: 'wholesale_item_id', dependent: :destroy
    
    # Virtual attribute for custom variant SKUs
    attr_accessor :custom_variant_skus
    
    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :price_cents, presence: true, numericality: { greater_than: 0 }
    validates :sku, uniqueness: { scope: :fundraiser_id }, allow_blank: true
    validates :position, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
    validates :sort_order, numericality: { greater_than_or_equal_to: 0 }
    validates :stock_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
    validates :low_stock_threshold, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
    
    # Custom validations
    validate :low_stock_threshold_requires_tracking
    validate :stock_quantity_requires_tracking
    
    # Callbacks
    before_save :set_last_restocked_at, if: -> { stock_quantity_changed? && stock_quantity_was.present? && stock_quantity > stock_quantity_was }
    before_save :reset_inventory_fields_if_tracking_disabled
    before_save :reset_damaged_quantity_if_tracking_enabled
    after_save :handle_variant_updates, if: -> { saved_change_to_options? || saved_change_to_sku? || saved_change_to_price_cents? }
    after_save :update_stock_status_after_save, if: -> { saved_change_to_stock_quantity? || saved_change_to_damaged_quantity? }
    
    # Scopes
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    scope :by_position, -> { order(:position, :sort_order, :name) }
    scope :by_sort_order, -> { order(:sort_order, :name) }
    scope :with_inventory_tracking, -> { where(track_inventory: true) }
    scope :without_inventory_tracking, -> { where(track_inventory: false) }
    scope :low_stock, -> { where(track_inventory: true).where('stock_quantity <= low_stock_threshold AND low_stock_threshold IS NOT NULL') }
    scope :out_of_stock, -> { where(track_inventory: true, stock_quantity: 0) }
    scope :unlimited_stock, -> { where(track_inventory: false) }
    scope :in_stock, -> { where('track_inventory = false OR (track_inventory = true AND stock_quantity > 0)') }
    
    # Price handling (in cents)
    def price
      (price_cents || 0) / 100.0
    end
    
    def price=(amount)
      if amount.is_a?(String)
        self.price_cents = (amount.to_f * 100).round
      else
        self.price_cents = (amount.to_f * 100).round
      end
    end
    
    # Inventory methods
    def track_inventory?
      track_inventory
    end
    
    def unlimited_stock?
      !track_inventory?
    end
    
    def in_stock?(quantity = 1)
      return true if unlimited_stock?
      stock_quantity >= quantity
    end
    
    def out_of_stock?
      track_inventory? && stock_quantity <= 0
    end
    
    def low_stock?
      return false unless track_inventory? && low_stock_threshold.present?
      stock_quantity <= low_stock_threshold
    end
    
    def available_quantity
      return Float::INFINITY unless track_inventory?
      return nil unless stock_quantity.present?
      
      total = stock_quantity.to_i
      damaged = damaged_quantity.to_i
      available = total - damaged
      
      Rails.logger.info("WHOLESALE INVENTORY DEBUG: available_quantity for #{id} (#{name}) - Stock: #{total}, Damaged: #{damaged}, Available: #{available}")
      
      [available, 0].max
    end
    
    def actual_low_stock_threshold
      low_stock_threshold || 10  # Default to 10 if not set
    end
    
    # Stock status enum (similar to regular MenuItem)
    enum :stock_status, {
      unlimited: 'unlimited',
      in_stock: 'in_stock',
      out_of_stock: 'out_of_stock',
      low_stock: 'low_stock'
    }, prefix: true
    
    def stock_status_display
      return 'unlimited' if unlimited_stock?
      return 'out_of_stock' if out_of_stock?
      return 'low_stock' if low_stock?
      'in_stock'
    end
    
    def can_purchase?(quantity = 1)
      return true if unlimited_stock?
      return true if allow_sale_with_no_stock? && track_inventory?
      quantity <= available_quantity
    end
    
    # Mark a quantity as damaged without affecting stock quantity
    def mark_as_damaged(quantity, reason, user = nil)
      return false unless track_inventory?

      transaction do
        # Create audit record for damaged item
        stock_audit = Wholesale::ItemStockAudit.create_damaged_record(self, quantity, reason, user)

        # Update the damaged quantity
        previous_damaged = self.damaged_quantity || 0
        self.update!(damaged_quantity: previous_damaged + quantity.to_i)

        # Re-evaluate stock status based on available quantity
        update_stock_status!

        true
      end
    rescue => e
      Rails.logger.error("Failed to mark wholesale item as damaged: #{e.message}")
      false
    end

    # Update stock quantity with audit trail
    def update_stock_quantity(new_quantity, reason_type, reason_details = nil, user = nil, order = nil)
      return false unless track_inventory?

      transaction do
        # Create audit record
        stock_audit = Wholesale::ItemStockAudit.create_stock_record(self, new_quantity, reason_type, reason_details, user, order)

        # Update the stock quantity
        self.update!(stock_quantity: new_quantity)
        self.update!(last_restocked_at: Time.current) if new_quantity > (stock_quantity_was || 0)

        # Re-evaluate stock status based on available quantity
        update_stock_status!

        true
      end
    rescue => e
      Rails.logger.error("Failed to update wholesale stock quantity: #{e.message}")
      false
    end

    # Update stock status based on available quantity
    def update_stock_status!
      return unless track_inventory?

      available = available_quantity
      return unless available.is_a?(Numeric) # Skip if unlimited or nil

      old_status = stock_status

      new_status = if available <= 0
                    :out_of_stock
      elsif available <= actual_low_stock_threshold
                    :low_stock
      else
                    :in_stock
      end

      # Only update if status has changed
      if stock_status != new_status.to_s
        update_column(:stock_status, new_status.to_s)
        
        Rails.logger.info("Wholesale item #{id} (#{name}) stock status changed from #{old_status} to #{new_status}")
      end
    end

    # Convenience methods with audit trail
    def restock!(quantity, notes: nil, user: nil)
      return false unless track_inventory?
      
      new_quantity = (stock_quantity || 0) + quantity
      update_stock_quantity(new_quantity, 'restock', notes, user)
    end
    
    def reduce_stock!(quantity, reason: 'manual_adjustment', user: nil, order: nil)
      return true if unlimited_stock?
      
      # Check availability with better error messaging
      unless in_stock?(quantity)
        available = available_quantity
        if available <= 0
          raise "#{name} is out of stock"
        else
          raise "Insufficient stock for #{name}. Only #{available} available (requested #{quantity})"
        end
      end
      
      new_quantity = (stock_quantity || 0) - quantity
      success = update_stock_quantity(new_quantity, reason, "Reduced by #{quantity}", user, order)
      
      unless success
        raise "Failed to reduce stock for #{name}"
      end
      
      success
    end
    
    def set_stock!(quantity, notes: nil, user: nil)
      return false unless track_inventory?
      
      update_stock_quantity(quantity, 'manual_adjustment', notes, user)
    end
    
    # Option-level inventory tracking methods (similar to regular MenuItem)
    def has_option_inventory_tracking?
      option_groups.any?(&:inventory_tracking_enabled?)
    end

    def option_inventory_tracking_group
      option_groups.find(&:inventory_tracking_enabled?)
    end

    def uses_option_level_inventory?
      # For mutual exclusivity: use option inventory when item tracking is OFF and option tracking is ON
      !track_inventory? && has_option_inventory_tracking?
    end

    # Check if option inventory totals match item inventory
    def option_inventory_matches_item_inventory?
      return true unless uses_option_level_inventory?
      
      tracking_group = option_inventory_tracking_group
      return true unless tracking_group
      
      tracking_group.total_option_stock == stock_quantity.to_i
    end

    # Get effective available quantity (considers item, option, and variant inventory)
    def effective_available_quantity
      if track_variants?
        # For variant tracking, return the sum of all active variant stock
        item_variants.active.sum(&:available_stock)
      elsif uses_option_level_inventory?
        tracking_group = option_inventory_tracking_group
        tracking_group&.available_option_stock || 0
      else
        available_quantity
      end
    end

    # Check if effectively out of stock (considers both item and option inventory)
    def effectively_out_of_stock?
      if uses_option_level_inventory?
        tracking_group = option_inventory_tracking_group
        tracking_group ? !tracking_group.has_option_stock? : true
      else
        track_inventory? && available_quantity <= 0
      end
    end
    
    # Image helpers
    def primary_image
      item_images.find_by(primary: true) || item_images.order(:position).first
    end
    
    def primary_image_url
      primary_image&.image_url
    end
    
    def all_image_urls
      item_images.order(:position).pluck(:image_url)
    end
    
    # Order statistics
    def total_ordered_quantity
      # All orders count as revenue since orders can only be created after payment
      order_items.joins(:order).sum(:quantity)
    end
    
    def total_revenue_cents
      # All orders count as revenue since orders can only be created after payment
      order_items.joins(:order).sum('quantity * price_cents')
    end
    
    # Variant management methods (public)
    # DEPRECATED: Use has_options? instead for the new option groups system
    def has_variants?
      Rails.logger.warn "DEPRECATED: has_variants? is deprecated. Use has_options? instead."
      return false unless options.is_a?(Hash)
      size_options = options['size_options'] || []
      color_options = options['color_options'] || []
      size_options.any? || color_options.any?
    end
    
    # Find variant by selected options
    # DEPRECATED: Use option groups system instead
    def find_variant_by_options(selected_options)
      Rails.logger.warn "DEPRECATED: find_variant_by_options is deprecated. Use option groups system instead."
      return nil unless has_variants? && selected_options.present?
      
      size = selected_options['size'] || selected_options[:size]
      color = selected_options['color'] || selected_options[:color]
      
      variants.find_by(size: size, color: color)
    end
    
    # ===== NEW OPTION GROUP METHODS =====
    
    # Check if item has option groups
    def has_options?
      option_groups.exists?
    end
    
    # Generate SKU for a specific option selection
    # selected_options format: { "group_id" => "option_id", "group_id" => "option_id" }
    def generate_sku_for_selection(selected_options = {})
      base_sku = sku.present? ? sku.upcase : "ITEM-#{id}"
      
      # Add option abbreviations to SKU
      option_parts = []
      option_groups.includes(:options).order(:position).each do |group|
        if selected_options[group.id.to_s].present?
          option = group.options.find_by(id: selected_options[group.id.to_s])
          if option
            option_parts << abbreviate_option_name(option.name)
          end
        end
      end
      
      option_parts.any? ? "#{base_sku}-#{option_parts.join('-')}" : base_sku
    end
    
    # Check if item has required option groups with no available options
    def has_required_unavailable_option_groups?
      option_groups.any?(&:required_but_unavailable?)
    end
    
    # Get list of required option groups with no available options
    def required_unavailable_option_groups
      option_groups.select(&:required_but_unavailable?)
    end
    
    # Check if item is effectively available (considering option availability)
    def effectively_available?
      return active unless has_options?
      active && !has_required_unavailable_option_groups?
    end
    
    # ===== OPTION-BASED ORDER PROCESSING METHODS =====
    
    # Calculate final price for a specific option selection
    # selected_options format: { "group_id" => "option_id", "group_id" => "option_id" }
    def calculate_price_for_options(selected_options = {})
      base_price = price_cents / 100.0
      additional_price = 0.0
      
      return base_price unless has_options? && selected_options.present?
      
      option_groups.includes(:options).each do |group|
        option_id = selected_options[group.id.to_s]
        if option_id.present?
          option = group.options.find_by(id: option_id)
          additional_price += option.additional_price if option
        end
      end
      
      base_price + additional_price
    end
    
    # Check if a specific option selection is available for purchase
    def can_purchase_with_options?(selected_options = {}, quantity = 1)
      return false unless active
      return false if has_required_unavailable_option_groups?
      
      # Check if all selected options are available
      if has_options? && selected_options.present?
        option_groups.includes(:options).each do |group|
          option_id = selected_options[group.id.to_s]
          if option_id.present?
            option = group.options.find_by(id: option_id)
            return false unless option&.available?
          elsif group.required?
            return false # Required group must have a selection
          end
        end
      end
      
      # Check inventory if tracking is enabled
      if track_inventory?
        return false unless can_purchase?(quantity)
      end
      
      true
    end
    
    # Validate that selected options meet group requirements
    def validate_option_selection(selected_options = {})
      errors = []
      
      return errors unless has_options?
      
      option_groups.includes(:options).each do |group|
        selected_option_ids = Array(selected_options[group.id.to_s]).compact
        
        # Check minimum selections
        if selected_option_ids.length < group.min_select
          errors << "#{group.name} requires at least #{group.min_select} selection(s)"
        end
        
        # Check maximum selections
        if selected_option_ids.length > group.max_select
          errors << "#{group.name} allows at most #{group.max_select} selection(s)"
        end
        
        # Check required groups
        if group.required? && selected_option_ids.empty?
          errors << "#{group.name} is required"
        end
        
        # Check that selected options exist and are available
        selected_option_ids.each do |option_id|
          option = group.options.find_by(id: option_id)
          if option.nil?
            errors << "Invalid option selected for #{group.name}"
          elsif !option.available?
            errors << "#{option.name} is not available in #{group.name}"
          end
        end
      end
      
      errors
    end
    
    # Track sales for specific option selections
    def track_option_sales!(selected_options = {}, quantity = 1, revenue = 0.0)
      return unless has_options? && selected_options.present?
      
      option_groups.includes(:options).each do |group|
        option_id = selected_options[group.id.to_s]
        if option_id.present?
          option = group.options.find_by(id: option_id)
          if option
            option.increment!(:total_ordered, quantity)
            option.increment!(:total_revenue, revenue)
          end
        end
      end
    end
    
    # Get display name for option selection
    def option_selection_display_name(selected_options = {})
      return name unless has_options? && selected_options.present?
      
      option_names = []
      option_groups.includes(:options).order(:position).each do |group|
        option_id = selected_options[group.id.to_s]
        if option_id.present?
          option = group.options.find_by(id: option_id)
          option_names << option.name if option
        end
      end
      
      if option_names.any?
        "#{name} (#{option_names.join(', ')})"
      else
        name
      end
    end
    
    private
    
        def low_stock_threshold_requires_tracking
      if low_stock_threshold.present? && !track_inventory?
        errors.add(:low_stock_threshold, 'can only be set when inventory tracking is enabled')
      end
    end

    def stock_quantity_requires_tracking
      if stock_quantity.present? && !track_inventory?
        errors.add(:stock_quantity, 'can only be set when inventory tracking is enabled')
      end
    end
    
    def set_last_restocked_at
      self.last_restocked_at = Time.current
    end
    
    # Simple abbreviation logic for option names
    def abbreviate_option_name(name)
      case name.upcase.strip
      when /^EXTRA\s*SMALL$|^XS$/ then 'XS'
      when /^SMALL$|^S$/ then 'S'
      when /^MEDIUM$|^M$/ then 'M'
      when /^LARGE$|^L$/ then 'L'
      when /^EXTRA\s*LARGE$|^XL$/ then 'XL'
      when /^XXL$|^2XL$|^EXTRA\s*EXTRA\s*LARGE$/ then 'XXL'
      when /^RED$/ then 'RED'
      when /^BLUE$/ then 'BLU'
      when /^GREEN$/ then 'GRN'
      when /^BLACK$/ then 'BLK'
      when /^WHITE$/ then 'WHI'
      when /^YELLOW$/ then 'YEL'
      when /^ORANGE$/ then 'ORG'
      when /^PURPLE$/ then 'PUR'
      when /^PINK$/ then 'PNK'
      when /^GRAY$|^GREY$/ then 'GRY'
      when /^NAVY$/ then 'NAV'
      else
        # For unknown options, take first 3 characters
        name.upcase.gsub(/\s+/, '').first(3)
      end
    end
    
    def handle_variant_updates
      # Parse custom_variant_skus if it's a JSON string
      parsed_custom_skus = nil
      if custom_variant_skus.present?
        parsed_custom_skus = custom_variant_skus.is_a?(String) ? JSON.parse(custom_variant_skus) : custom_variant_skus
      end
      
      create_or_update_variants(parsed_custom_skus)
    end
    
    # DEPRECATED: Use option groups system instead
    def create_or_update_variants(custom_skus = nil)
      Rails.logger.warn "DEPRECATED: create_or_update_variants is deprecated. Use option groups system instead."
      return unless has_variants?
      
      # Get current variant combinations
      current_variants = generate_variant_combinations(custom_skus)
      
      # Remove variants that no longer exist
      if current_variants.any?
        # Build conditions to keep variants that match current combinations
        keep_conditions = current_variants.map do |v|
          if v[:size].present? && v[:color].present?
            "(size = '#{v[:size]}' AND color = '#{v[:color]}')"
          elsif v[:size].present?
            "(size = '#{v[:size]}' AND color IS NULL)"
          elsif v[:color].present?
            "(color = '#{v[:color]}' AND size IS NULL)"
          end
        end.compact.join(' OR ')
        
        variants.where.not(keep_conditions).destroy_all if keep_conditions.present?
      else
        # No variants should exist, remove all
        variants.destroy_all
      end
      
      # Create or update variants
      current_variants.each do |variant_data|
        variant = variants.find_or_initialize_by(
          size: variant_data[:size],
          color: variant_data[:color]
        )
        
        # Always update SKU as it may have changed due to base SKU changes
        variant.sku = variant_data[:sku]
        
        # For new variants, set default values
        if variant.new_record?
          variant.price_adjustment = 0.0
          variant.active = true
          variant.stock_quantity = track_inventory? ? (stock_quantity || 0) : 0
          variant.low_stock_threshold = low_stock_threshold || 5
          variant.total_ordered = 0
          variant.total_revenue = 0.0
        end
        # For existing variants, preserve their current settings (active, price_adjustment, etc.)
        
        variant.save!
      end
    end
    
    def generate_variant_combinations(custom_skus = nil)
      return [] unless has_variants?
      
      size_options = options['size_options'] || []
      color_options = options['color_options'] || []
      base_sku = sku.present? ? sku.upcase : "ITEM-#{id}"
      
      combinations = []
      index = 0
      
      if size_options.any? && color_options.any?
        # Both sizes and colors - create all combinations
        color_options.each do |color|
          size_options.each do |size|
            custom_sku = custom_skus&.dig(index.to_s) || custom_skus&.dig(index)
            combinations << {
              size: size,
              color: color,
              sku: custom_sku || generate_variant_sku(base_sku, color, size)
            }
            index += 1
          end
        end
      elsif size_options.any?
        # Only sizes
        size_options.each do |size|
          custom_sku = custom_skus&.dig(index.to_s) || custom_skus&.dig(index)
          combinations << {
            size: size,
            color: nil,
            sku: custom_sku || generate_variant_sku(base_sku, nil, size)
          }
          index += 1
        end
      elsif color_options.any?
        # Only colors
        color_options.each do |color|
          custom_sku = custom_skus&.dig(index.to_s) || custom_skus&.dig(index)
          combinations << {
            size: nil,
            color: color,
            sku: custom_sku || generate_variant_sku(base_sku, color, nil)
          }
          index += 1
        end
      end
      
      combinations
    end
    
    def generate_variant_sku(base_sku, color, size)
      parts = [base_sku]
      
      if color.present?
        color_code = color.gsub(/\s+/, '').upcase[0, 3]
        parts << color_code
      end
      
      if size.present?
        size_code = size.gsub(/\s+/, '').upcase
        parts << size_code
      end
      
      parts.join('-')
    end
    
    private
    
    # Reset inventory tracking fields when tracking is turned off
    def reset_inventory_fields_if_tracking_disabled
      if track_inventory_changed? && !track_inventory?
        # Set inventory fields to NULL in the database
        self.stock_quantity = nil
        self.damaged_quantity = 0
        self.low_stock_threshold = nil
        self.stock_status = "unlimited"
        
        # Also reset ALL option quantities when item tracking is disabled
        reset_all_option_quantities("Item inventory tracking disabled")
        
        Rails.logger.info("Wholesale item #{id} (#{name}) - Inventory tracking disabled: fields reset")
      end
    end

    # Reset damaged quantity to 0 when tracking is enabled
    def reset_damaged_quantity_if_tracking_enabled
      if track_inventory_changed? && track_inventory?
        self.damaged_quantity = 0
        self.stock_status = "in_stock"
        
        Rails.logger.info("Wholesale item #{id} (#{name}) - Inventory tracking enabled: damaged_quantity reset to 0 for fresh start")
        
        # Also reset ALL option quantities when item tracking is enabled for fresh start
        reset_all_option_quantities("Item inventory tracking enabled - fresh start")
      end
    end
    
    # Reset all option quantities (when item tracking changes)
    def reset_all_option_quantities(reason)
      option_groups.includes(:options).each do |group|
        group.options.each do |option|
          if option.stock_quantity.present? && option.stock_quantity > 0
            option.update_columns(
              stock_quantity: nil,
              damaged_quantity: 0
            )
          end
        end
      end
    end
    
    # Update stock status after save if quantities changed
    def update_stock_status_after_save
      update_stock_status! if track_inventory?
    end
    
    # ========================================
    # VARIANT TRACKING METHODS
    # ========================================
    
    public
    
    # Check if this item uses variant-level inventory tracking
    def track_variants?
      track_variants == true
    end
    
    # Generate a variant key from selected options
    # Format: "groupId:optionId,groupId:optionId" (sorted by group ID)
    def generate_variant_key(selected_options)
      return nil if selected_options.blank?
      
      # Convert to consistent format and sort by group ID
      key_parts = selected_options.map do |group_id, option_ids|
        group_id = group_id.to_s
        option_ids = Array(option_ids).map(&:to_s).sort
        option_ids.map { |option_id| "#{group_id}:#{option_id}" }
      end.flatten.sort
      
      key_parts.join(',')
    end
    
    # Generate human-readable variant name from selected options
    def generate_variant_name(selected_options)
      return nil if selected_options.blank?
      
      option_names = []
      selected_options.each do |group_id, option_ids|
        group = option_groups.find { |g| g.id.to_s == group_id.to_s }
        next unless group
        
        Array(option_ids).each do |option_id|
          option = group.options.find { |o| o.id.to_s == option_id.to_s }
          option_names << option.name if option
        end
      end
      
      option_names.join(', ')
    end
    
    # Find variant by selected options
    def find_variant_by_options(selected_options)
      return nil unless track_variants?
      variant_key = generate_variant_key(selected_options)
      return nil if variant_key.blank?
      
      item_variants.find_by(variant_key: variant_key)
    end
    
    # Get available stock for a specific variant
    def get_variant_stock(selected_options)
      return nil unless track_variants?
      variant = find_variant_by_options(selected_options)
      variant&.available_stock || 0
    end
    
    # Check if a variant is in stock
    def variant_in_stock?(selected_options, quantity = 1)
      return true unless track_variants?
      variant = find_variant_by_options(selected_options)
      return false unless variant
      variant.in_stock?(quantity)
    end
    
    # Get all possible variant combinations for this item
    def generate_all_variant_combinations
      return [] unless has_options?
      
      # Get all option groups with their options
      groups_with_options = option_groups.includes(:options).map do |group|
        {
          group_id: group.id,
          group_name: group.name,
          options: group.options.active.map { |opt| { id: opt.id, name: opt.name } }
        }
      end
      
      # Generate all combinations
      combinations = []
      generate_combinations_recursive(groups_with_options, {}, combinations)
      combinations
    end
    
    public
    
    # Create variants for all possible combinations
    def create_all_variants!(default_stock = 0)
      return false unless track_variants?
      
      combinations = generate_all_variant_combinations
      created_variants = []
      
      transaction do
        combinations.each do |combination|
          variant_key = generate_variant_key(combination[:selected_options])
          variant_name = generate_variant_name(combination[:selected_options])
          
          variant = item_variants.find_or_initialize_by(variant_key: variant_key)
          variant.assign_attributes(
            variant_name: variant_name,
            stock_quantity: variant.persisted? ? variant.stock_quantity : default_stock,
            active: true
          )
          
          if variant.save
            created_variants << variant
          else
            Rails.logger.error("Failed to create variant: #{variant.errors.full_messages}")
          end
        end
      end
      
      created_variants
    end
    
    private
    
    # Recursive helper for generating variant combinations
    def generate_combinations_recursive(groups_with_options, current_selection, combinations, group_index = 0)
      if group_index >= groups_with_options.length
        # We've made selections for all groups, add this combination
        combinations << {
          selected_options: current_selection.dup,
          display_name: generate_variant_name(current_selection)
        }
        return
      end
      
      current_group = groups_with_options[group_index]
      
      # For each option in the current group
      current_group[:options].each do |option|
        # Add this option to the current selection
        current_selection[current_group[:group_id]] = [option[:id]]
        
        # Recurse to the next group
        generate_combinations_recursive(groups_with_options, current_selection, combinations, group_index + 1)
      end
      
      # Clean up the current selection for this group
      current_selection.delete(current_group[:group_id])
    end
  end
end