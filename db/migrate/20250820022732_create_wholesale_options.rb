class CreateWholesaleOptions < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_options do |t|
      t.references :wholesale_option_group, null: false, foreign_key: { to_table: :wholesale_option_groups }
      t.string :name, null: false # "Small", "Red", etc.
      t.decimal :additional_price, precision: 8, scale: 2, default: 0.0
      t.boolean :available, default: true # Key field for availability
      t.integer :position, default: 0
      
      # Future inventory fields (nullable for now)
      t.integer :stock_quantity, null: true
      t.integer :damaged_quantity, default: 0
      t.integer :low_stock_threshold, null: true
      
      # Sales analytics
      t.integer :total_ordered, default: 0
      t.decimal :total_revenue, precision: 10, scale: 2, default: 0.0
      
      t.timestamps
    end
    
    add_index :wholesale_options, :position
    add_index :wholesale_options, :available
    add_index :wholesale_options, [:wholesale_option_group_id, :name], 
              name: 'idx_wholesale_options_group_name', unique: true
  end
end