class AddPerformanceIndexes < ActiveRecord::Migration[7.2]
  def change
    # Orders - speed up filtering by restaurant and status
    add_index :orders, [:restaurant_id, :status], name: 'index_orders_on_restaurant_id_and_status'
    
    # Orders - speed up user order history
    add_index :orders, [:user_id, :created_at], name: 'index_orders_on_user_id_and_created_at'
    
    # Order acknowledgments - speed up filtering by time
    add_index :order_acknowledgments, :acknowledged_at, name: 'index_order_acknowledgments_on_acknowledged_at'
    
    # Menu items - speed up availability filtering
    add_index :menu_items, [:menu_id, :available], name: 'index_menu_items_on_menu_id_and_available'
    
    # Menu items - speed up category filtering
    add_index :menu_items, [:menu_id, :category], name: 'index_menu_items_on_menu_id_and_category'
    
    # Users - speed up phone verification
    add_index :users, :phone, where: "phone IS NOT NULL", name: 'index_users_on_phone_not_null'
  end
end
