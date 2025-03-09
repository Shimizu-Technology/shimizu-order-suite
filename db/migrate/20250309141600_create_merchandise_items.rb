class CreateMerchandiseItems < ActiveRecord::Migration[7.2]
  def change
    create_table :merchandise_items do |t|
      t.string :name, null: false
      t.text :description
      t.decimal :base_price, precision: 8, scale: 2, default: 0.0
      t.string :image_url
      t.boolean :available, default: true
      t.integer :stock_status, default: 0
      t.text :status_note
      t.references :merchandise_collection, null: false, foreign_key: true
      
      t.timestamps
    end
    
    add_index :merchandise_items, [:merchandise_collection_id, :available]
  end
end
