class AddFulfillmentMethodToOrders < ActiveRecord::Migration[7.2]
  def change
    # Add new columns for fulfillment method and pickup location
    add_column :orders, :fulfillment_method, :string, default: 'pickup'
    add_column :orders, :pickup_location_id, :bigint
    
    # Add index for pickup_location_id
    add_index :orders, :pickup_location_id
    
    # Add foreign key for pickup_location_id
    add_foreign_key :orders, :locations, column: :pickup_location_id
    
    # Update existing records to set pickup_location_id equal to location_id
    # and fulfillment_method to 'pickup' for backward compatibility
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE orders 
          SET pickup_location_id = location_id,
              fulfillment_method = 'pickup'
          WHERE pickup_location_id IS NULL;
        SQL
      end
    end
  end
end
