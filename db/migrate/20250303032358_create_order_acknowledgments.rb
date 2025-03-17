class CreateOrderAcknowledgments < ActiveRecord::Migration[7.2]
  def change
    create_table :order_acknowledgments do |t|
      t.references :order, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :acknowledged_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps

      # Ensure a user can only acknowledge an order once
      t.index [ :order_id, :user_id ], unique: true
    end
  end
end
