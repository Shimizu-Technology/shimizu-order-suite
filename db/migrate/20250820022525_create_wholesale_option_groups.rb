class CreateWholesaleOptionGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_option_groups do |t|
      t.references :wholesale_item, null: false, foreign_key: { to_table: :wholesale_items }
      t.string :name, null: false # "Size", "Color", etc.
      t.integer :min_select, default: 0
      t.integer :max_select, default: 1
      t.boolean :required, default: false
      t.integer :position, default: 0
      t.boolean :enable_inventory_tracking, default: false # For future use
      t.timestamps
    end
    
    add_index :wholesale_option_groups, :position
    add_index :wholesale_option_groups, [:wholesale_item_id, :enable_inventory_tracking], 
              name: 'idx_wholesale_option_groups_item_inventory_tracking'
  end
end