# db/migrate/20250926004000_create_inventory_statuses.rb
class CreateInventoryStatuses < ActiveRecord::Migration[7.2]
  def change
    create_table :inventory_statuses do |t|
      t.references :menu_item, null: false, foreign_key: true
      t.integer :quantity, default: 0
      t.boolean :in_stock, default: true
      t.boolean :low_stock, default: false
      t.timestamps
    end
  end
end
