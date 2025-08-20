module Wholesale
  class OptionGroup < ApplicationRecord
    self.table_name = 'wholesale_option_groups'
    
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
    
    # Get total stock across all options (future feature)
    def total_option_stock
      return 0 unless inventory_tracking_enabled?
      options.sum(:stock_quantity)
    end
    
    # Get available stock across all options (future feature)
    def available_option_stock
      return 0 unless inventory_tracking_enabled?
      options.sum('COALESCE(stock_quantity, 0) - COALESCE(damaged_quantity, 0)')
    end
    
    # Check if any options have stock (future feature)
    def has_option_stock?
      return false unless inventory_tracking_enabled?
      available_option_stock > 0
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