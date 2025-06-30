class AddTrackingMethodToMenuItemStockAudits < ActiveRecord::Migration[7.2]
  def up
    # Add the column with a default value
    add_column :menu_item_stock_audits, :tracking_method, :string, default: 'menu_item'
    
    # Backfill existing data based on reason patterns
    execute <<~SQL
      UPDATE menu_item_stock_audits 
      SET tracking_method = 'option_level'
      WHERE reason LIKE '%(%)%' 
         OR reason LIKE '%- S%' 
         OR reason LIKE '%- M%' 
         OR reason LIKE '%- L%' 
         OR reason LIKE '%- XL%'
         OR reason LIKE '%option%'
         OR reason LIKE '%size%'
         OR reason LIKE '%variant%';
    SQL
    
    # Also mark audits as option_level if the menu item currently has option tracking enabled
    # This catches cases like damage audits that don't have option indicators in the reason
    execute <<~SQL
      UPDATE menu_item_stock_audits 
      SET tracking_method = 'option_level'
      WHERE menu_item_id IN (
        SELECT DISTINCT mi.id 
        FROM menu_items mi
        JOIN option_groups og ON og.menu_item_id = mi.id
        WHERE og.enable_inventory_tracking = true
      );
    SQL
    
    # Add index for better query performance
    add_index :menu_item_stock_audits, :tracking_method
  end
  
  def down
    remove_index :menu_item_stock_audits, :tracking_method
    remove_column :menu_item_stock_audits, :tracking_method
  end
end
