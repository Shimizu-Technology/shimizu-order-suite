class AddRestaurantIdToCategories < ActiveRecord::Migration[7.2]
  def change
    # First add the column as nullable
    add_reference :categories, :restaurant, null: true, foreign_key: true
    
    # Add data migration to set default restaurant_id for existing categories
    # For now, assign all existing categories to the first restaurant
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE categories SET restaurant_id = (SELECT id FROM restaurants LIMIT 1)
          WHERE restaurant_id IS NULL;
        SQL
      end
    end
    
    # After data migration, make the column not null
    change_column_null :categories, :restaurant_id, false
  end
end
