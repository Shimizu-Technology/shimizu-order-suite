class CreateFundraiserItems < ActiveRecord::Migration[7.2]
  def change
    create_table :fundraiser_items do |t|
      t.references :fundraiser, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.decimal :price, precision: 10, scale: 2, null: false, default: 0
      t.string :image_url
      t.boolean :active, default: true, null: false
      t.integer :stock_quantity, default: 0
      t.boolean :enable_stock_tracking, default: false, null: false
      t.integer :low_stock_threshold

      t.timestamps
    end
    
    # Add indexes for efficient querying
    add_index :fundraiser_items, [:fundraiser_id, :active]
    add_index :fundraiser_items, [:fundraiser_id, :name]
  end
end
