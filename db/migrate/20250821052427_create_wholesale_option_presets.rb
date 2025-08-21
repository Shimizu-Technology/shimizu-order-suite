class CreateWholesaleOptionPresets < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_option_presets do |t|
      t.references :wholesale_option_group_preset, null: false, foreign_key: true
      t.string :name, null: false
      t.decimal :additional_price, precision: 8, scale: 2, default: 0.0
      t.boolean :available, default: true
      t.integer :position, default: 0

      t.timestamps
    end
    
    add_index :wholesale_option_presets, :wholesale_option_group_preset_id, 
              name: 'index_wholesale_option_presets_on_group_preset_id'
    add_index :wholesale_option_presets, [:wholesale_option_group_preset_id, :name], 
              unique: true, name: 'idx_wholesale_option_presets_group_name'
    add_index :wholesale_option_presets, :position
    add_index :wholesale_option_presets, :available
  end
end
