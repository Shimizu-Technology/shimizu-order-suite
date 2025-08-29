module Wholesale
  class OptionGroup < ApplicationRecord
    self.table_name = 'wholesale_option_groups'
    
    # Soft delete support
    scope :active, -> { where(deleted_at: nil) }
    scope :deleted, -> { where.not(deleted_at: nil) }
    
    belongs_to :wholesale_item, class_name: 'Wholesale::Item', foreign_key: 'wholesale_item_id'
    has_many :options, class_name: 'Wholesale::Option', foreign_key: 'wholesale_option_group_id', dependent: :destroy
    
    validates :name, presence: true
    validates :min_select, numericality: { greater_than_or_equal_to: 0 }
    validates :max_select, numericality: { greater_than_or_equal_to: 1 }
    validate :max_select_greater_than_min_select
    
    # Only one option group per item can have inventory tracking (future feature)
    validate :only_one_inventory_tracking_group_per_item
    
    scope :by_position, -> { order(:position) }
    scope :required, -> { where(required: true) }
    scope :optional, -> { where(required: false) }
    
    # Check if this option group has any available options
    def has_available_options?
      options.where(available: true).exists?
    end
    
    # Check if this is a required group with no available options
    def required_but_unavailable?
      required? && !has_available_options?
    end
    
    # Check if inventory tracking is enabled for this group
    def inventory_tracking_enabled?
      enable_inventory_tracking == true
    end
    
    # Get total stock across all options
    def total_option_stock
      return 0 unless inventory_tracking_enabled?
      options.active.sum { |option| option.stock_quantity || 0 }
    end
    
    # Get available stock across all options (total - damaged)
    def available_option_stock
      return 0 unless inventory_tracking_enabled?
      options.active.sum { |option| option.available_stock || 0 }
    end
    
    # Check if any options have stock
    def has_option_stock?
      return false unless inventory_tracking_enabled?
      options.active.any? { |option| option.in_stock? }
    end
    
    # Get options that are in stock
    def in_stock_options
      return options.active unless inventory_tracking_enabled?
      options.active.select { |option| option.in_stock? }
    end
    
    # Get options that are out of stock
    def out_of_stock_options
      return [] unless inventory_tracking_enabled?
      options.active.select { |option| option.out_of_stock? }
    end
    
    # Get options that are low stock
    def low_stock_options
      return [] unless inventory_tracking_enabled?
      options.active.select { |option| option.low_stock? }
    end
    
    # Sync option inventory with item inventory (distribute proportionally)
    def sync_with_item_inventory!(target_total)
      return false unless inventory_tracking_enabled?
      
      current_total = total_option_stock
      return true if current_total == target_total
      
      difference = target_total - current_total
      distribute_stock_difference_to_options(difference)
      
      true
    end
    
    private
    
    # Distribute stock difference across options proportionally
    def distribute_stock_difference_to_options(difference)
      options_with_stock = options.active.where('stock_quantity > 0')
      return if options_with_stock.empty? && difference < 0
      
      if options_with_stock.empty? && difference > 0
        # If no options have stock but we need to add, distribute evenly
        options_to_update = options.active
      else
        options_to_update = options_with_stock
      end
      
      return if options_to_update.empty?
      
      # Simple proportional distribution
      per_option = difference / options_to_update.count
      remainder = difference % options_to_update.count
      
      options_to_update.each_with_index do |option, index|
        additional = index < remainder ? 1 : 0
        new_quantity = [option.stock_quantity.to_i + per_option + additional, 0].max
        option.update_column(:stock_quantity, new_quantity)
      end
    end
    
    # Soft delete methods
    def soft_delete!
      return false if used_in_orders?
      update!(deleted_at: Time.current)
    end
    
    def deleted?
      deleted_at.present?
    end
    
    def restore!
      update!(deleted_at: nil)
    end
    
    # Check if this option group is used in any orders
    def used_in_orders?
      # Check if any order items reference this option group ID in their selected_options
      Wholesale::OrderItem.joins(:order)
        .where("selected_options ? :group_id", group_id: id.to_s)
        .exists?
    end
    
    private
    
    def max_select_greater_than_min_select
      if min_select.present? && max_select.present? && max_select < min_select
        errors.add(:max_select, "must be greater than or equal to min_select")
      end
    end
    
    def only_one_inventory_tracking_group_per_item
      return unless enable_inventory_tracking && wholesale_item
      
      other_tracking_groups = wholesale_item.option_groups.where(enable_inventory_tracking: true)
      other_tracking_groups = other_tracking_groups.where.not(id: id) if persisted?
      
      if other_tracking_groups.exists?
        errors.add(:enable_inventory_tracking, "only one option group per item can have inventory tracking enabled")
      end
    end
  end
end