class AddOrderNumberToOrders < ActiveRecord::Migration[7.2]
  def change
    # Only add the column if it doesn't exist
    unless column_exists?(:orders, :order_number)
      add_column :orders, :order_number, :string
    end
    
    # Add indexes with if_not_exists to prevent errors
    add_index :orders, :order_number, unique: true, if_not_exists: true
    
    # Add a composite index for restaurant_id and order_number for faster lookups
    add_index :orders, [:restaurant_id, :order_number], if_not_exists: true
  end
end
