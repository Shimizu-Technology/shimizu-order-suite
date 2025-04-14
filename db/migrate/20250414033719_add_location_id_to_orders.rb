class AddLocationIdToOrders < ActiveRecord::Migration[7.2]
  def change
    # Make it nullable initially since we're adding to an existing table with data
    add_reference :orders, :location, null: true, foreign_key: true
    
    # Add an index to improve query performance when filtering orders by location
    add_index :orders, [:restaurant_id, :location_id]
  end
end
