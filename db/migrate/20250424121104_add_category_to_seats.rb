class AddCategoryToSeats < ActiveRecord::Migration[7.2]
  def change
    # Add category field with default 'standard' value
    add_column :seats, :category, :string, default: 'standard'
    
    # Add an index for faster lookups and filtering
    add_index :seats, :category
    
    # Add a check constraint to ensure category is one of the allowed values
    valid_categories = ["standard", "booth", "outdoor", "bar", "private", "high_top"]
    category_check = valid_categories.map { |c| "'#{c}'" }.join(', ')
    add_check_constraint :seats, "category IN (#{category_check})", name: "check_seat_category_values"
  end
end
