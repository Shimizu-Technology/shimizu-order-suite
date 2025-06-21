class SeedDefaultStaffDiscounts < ActiveRecord::Migration[7.2]
  def up
    # Create default discount configurations for all restaurants
    Restaurant.find_each do |restaurant|
      # On Duty discount
      restaurant.staff_discount_configurations.find_or_create_by(code: 'on_duty') do |config|
        config.name = 'On Duty'
        config.discount_percentage = 50.0
        config.discount_type = 'percentage'
        config.is_active = true
        config.is_default = true
        config.display_order = 1
        config.description = 'Standard discount for staff members currently on duty'
        config.ui_color = '#10B981'  # Green
      end

      # Off Duty discount
      restaurant.staff_discount_configurations.find_or_create_by(code: 'off_duty') do |config|
        config.name = 'Off Duty'
        config.discount_percentage = 30.0
        config.discount_type = 'percentage'
        config.is_active = true
        config.is_default = false
        config.display_order = 2
        config.description = 'Standard discount for off-duty staff members'
        config.ui_color = '#F59E0B'  # Amber
      end

      # No Discount option
      restaurant.staff_discount_configurations.find_or_create_by(code: 'no_discount') do |config|
        config.name = 'No Discount'
        config.discount_percentage = 0.0
        config.discount_type = 'percentage'
        config.is_active = true
        config.is_default = false
        config.display_order = 3
        config.description = 'Full price with no discount applied'
        config.ui_color = '#6B7280'  # Gray
      end
    end
  end

  def down
    # Remove all staff discount configurations
    StaffDiscountConfiguration.delete_all
  end
end 