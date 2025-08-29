class AddInventoryFieldsToWholesaleItems < ActiveRecord::Migration[7.2]
  def change
    add_column :wholesale_items, :damaged_quantity, :integer, default: 0, null: false
    add_column :wholesale_items, :stock_status, :string, default: 'unlimited', null: false
    
    # Add indexes for performance
    add_index :wholesale_items, :stock_status
    add_index :wholesale_items, [:track_inventory, :stock_status]
    
    # Update existing items to have proper defaults
    # All existing items will have unlimited stock (track_inventory = false by default)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE wholesale_items 
          SET damaged_quantity = 0, stock_status = 'unlimited' 
          WHERE damaged_quantity IS NULL OR stock_status IS NULL
        SQL
      end
    end
  end
end
