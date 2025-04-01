class AddGlobalLastAcknowledgedAtToOrders < ActiveRecord::Migration[7.2]
  def change
    add_column :orders, :global_last_acknowledged_at, :datetime
    add_index :orders, :global_last_acknowledged_at
  end
end