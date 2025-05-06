class AddLocationIdToLayouts < ActiveRecord::Migration[7.2]
  def change
    add_column :layouts, :location_id, :bigint, null: true
    add_index :layouts, :location_id
    add_foreign_key :layouts, :locations
  end
end
