# db/migrate/20250120150000_add_current_layout_id_to_restaurants.rb
class AddCurrentLayoutIdToRestaurants < ActiveRecord::Migration[7.2]
  def change
    # 1) Add the column (bigint)
    add_column :restaurants, :current_layout_id, :bigint

    # 2) Add a foreign key from restaurants.current_layout_id => layouts.id
    #    'on_delete: :nullify' is optional, but it means if a layout is destroyed,
    #    this pointer becomes nil instead of blocking the deletion.
    add_foreign_key :restaurants, :layouts, column: :current_layout_id, on_delete: :nullify

    # 3) (Optional) Add an index for quicker lookups
    add_index :restaurants, :current_layout_id
  end
end
