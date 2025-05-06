class AddCurrentLayoutIdToLocations < ActiveRecord::Migration[7.2]
  def change
    add_column :locations, :current_layout_id, :bigint
    add_index :locations, :current_layout_id
    add_foreign_key :locations, :layouts, column: :current_layout_id, on_delete: :nullify
  end
end
