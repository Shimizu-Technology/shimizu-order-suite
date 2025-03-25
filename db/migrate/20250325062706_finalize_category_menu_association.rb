class FinalizeCategoryMenuAssociation < ActiveRecord::Migration[7.2]
  def change
    # Make menu_id required
    change_column_null :categories, :menu_id, false
    
    # Remove old index and uniqueness constraint
    remove_index :categories, name: "index_categories_on_restaurant_id" if index_exists?(:categories, :restaurant_id)
    remove_index :categories, name: "index_categories_on_restaurant_id_and_name" if index_exists?(:categories, [:restaurant_id, :name])
    
    # Remove restaurant_id
    remove_reference :categories, :restaurant
  end
end
