class AddUniqueIndexOnOrdersRestaurantTransactionId < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    add_index :orders,
              [ :restaurant_id, :transaction_id ],
              unique: true,
              where: "transaction_id IS NOT NULL AND transaction_id <> '' AND transaction_id NOT LIKE 'TEST-%' AND payment_status NOT IN ('canceled','refunded')",
              algorithm: :concurrently,
              name: "idx_orders_unique_restaurant_transaction_id_real"
  end

  def down
    remove_index :orders, name: "idx_orders_unique_restaurant_transaction_id_real", algorithm: :concurrently
  end
end
