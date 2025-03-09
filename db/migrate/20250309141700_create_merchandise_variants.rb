class CreateMerchandiseVariants < ActiveRecord::Migration[7.2]
  def change
    create_table :merchandise_variants do |t|
      t.references :merchandise_item, null: false, foreign_key: true
      t.string :size
      t.string :color
      t.string :sku
      t.decimal :price_adjustment, precision: 8, scale: 2, default: 0.0
      t.integer :stock_quantity, default: 0
      
      t.timestamps
    end
    
    add_index :merchandise_variants, [:merchandise_item_id, :size, :color], name: 'index_merch_variants_on_item_size_color'
  end
end
