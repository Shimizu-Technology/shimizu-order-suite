class AddCreatedByUserIdToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :created_by_user, null: true, foreign_key: { to_table: :users }
  end
end
