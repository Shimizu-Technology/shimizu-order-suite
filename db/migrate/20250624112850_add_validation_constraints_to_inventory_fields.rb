class AddValidationConstraintsToInventoryFields < ActiveRecord::Migration[7.2]
  def change
    # Add check constraints to ensure stock quantities are non-negative
    add_check_constraint :options, "stock_quantity >= 0", name: "check_options_stock_quantity_non_negative"
    add_check_constraint :options, "damaged_quantity >= 0", name: "check_options_damaged_quantity_non_negative"
  end
end
