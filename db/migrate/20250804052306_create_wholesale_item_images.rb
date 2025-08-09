class CreateWholesaleItemImages < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_item_images do |t|
      t.references :item, null: false, foreign_key: { to_table: :wholesale_items }
      t.string :image_url, null: false
      t.string :alt_text
      t.integer :position, default: 1
      t.boolean :primary, default: false
      
      t.timestamps
    end
    
    # Index for ordering images by position
    add_index :wholesale_item_images, [:item_id, :position]
  end
end
