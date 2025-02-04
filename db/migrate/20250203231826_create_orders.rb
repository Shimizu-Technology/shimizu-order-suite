# db/migrate/20250926000000_create_orders.rb
class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      # If you have a restaurants table and want to link orders to a restaurant:
      t.references :restaurant, null: false, foreign_key: true

      # Link to a user if you want to track which logged-in user placed the order (optional).
      # If you allow guest checkout, you can make this optional with null: true.
      t.references :user, null: true, foreign_key: { to_table: :users }

      # Store the entire cart's line items in JSON, or you can create a separate order_items table.
      # Example structure: [{ "item_id": "...", "name": "...", "quantity": 1, "price": 9.99, "customizations": {...} }]
      t.jsonb :items, default: []

      # Basic fields
      t.string :status, null: false, default: 'pending'  # e.g., pending, preparing, ready, completed, cancelled
      t.decimal :total, precision: 10, scale: 2, null: false, default: 0
      t.string :promo_code
      t.text :special_instructions
      t.datetime :estimated_pickup_time

      t.timestamps
    end

    # Optional: add a constraint on status if you want to limit possible values:
    # execute <<-SQL
    #   ALTER TABLE orders
    #   ADD CONSTRAINT check_order_status
    #   CHECK (status IN ('pending','preparing','ready','completed','cancelled'));
    # SQL
  end
end
