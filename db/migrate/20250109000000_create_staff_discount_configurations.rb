class CreateStaffDiscountConfigurations < ActiveRecord::Migration[7.2]
  def change
    create_table :staff_discount_configurations do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name, null: false, limit: 100  # "Off Duty", "On Duty", "Event Special", etc.
      t.string :code, null: false, limit: 50   # "off_duty", "on_duty", "event_special", etc.
      t.decimal :discount_percentage, precision: 5, scale: 2, null: false  # 30.00, 50.00, etc.
      t.string :discount_type, null: false, default: 'percentage', limit: 20  # 'percentage', 'fixed_amount' for future
      t.boolean :is_active, default: true, null: false
      t.boolean :is_default, default: false, null: false
      t.integer :display_order, default: 0, null: false
      t.text :description  # Optional description for admins
      t.string :ui_color, limit: 7  # Optional hex color for UI (e.g., "#c1902f")
      
      t.timestamps
    end

    # Indexes for performance
    add_index :staff_discount_configurations, [:restaurant_id, :is_active], name: 'idx_staff_discounts_restaurant_active'
    add_index :staff_discount_configurations, [:restaurant_id, :code], unique: true, name: 'idx_staff_discounts_restaurant_code'
    add_index :staff_discount_configurations, [:restaurant_id, :display_order], name: 'idx_staff_discounts_display_order'
    
    # Constraints
    add_check_constraint :staff_discount_configurations, 
                        "discount_percentage >= 0 AND discount_percentage <= 100", 
                        name: "chk_discount_percentage_range"
    add_check_constraint :staff_discount_configurations, 
                        "discount_type IN ('percentage', 'fixed_amount')", 
                        name: "chk_discount_type_values"
  end
end 