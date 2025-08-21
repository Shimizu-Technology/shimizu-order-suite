class CreateWholesaleOptionGroupPresets < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_option_group_presets do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :min_select, default: 0
      t.integer :max_select, default: 1
      t.boolean :required, default: false
      t.integer :position, default: 0
      t.boolean :enable_inventory_tracking, default: false

      t.timestamps
    end
    
    add_index :wholesale_option_group_presets, [:restaurant_id, :name], unique: true
    add_index :wholesale_option_group_presets, :position
  end
end
