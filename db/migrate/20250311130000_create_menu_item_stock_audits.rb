class CreateMenuItemStockAudits < ActiveRecord::Migration[7.2]
  def change
    create_table :menu_item_stock_audits do |t|
      t.references :menu_item, null: false, foreign_key: true
      t.integer :previous_quantity, null: false
      t.integer :new_quantity, null: false
      t.string :reason
      t.references :user, foreign_key: true
      t.references :order, foreign_key: true
      
      t.timestamps
    end
    
    add_index :menu_item_stock_audits, :created_at
  end
end
