class BackfillGlobalLastAcknowledgedAt < ActiveRecord::Migration[7.2]
  def up
    # For each order that has at least one acknowledgment,
    # set global_last_acknowledged_at to the earliest acknowledgment time
    execute <<-SQL
      UPDATE orders
      SET global_last_acknowledged_at = (
        SELECT MIN(acknowledged_at)
        FROM order_acknowledgments
        WHERE order_acknowledgments.order_id = orders.id
      )
      WHERE EXISTS (
        SELECT 1
        FROM order_acknowledgments
        WHERE order_acknowledgments.order_id = orders.id
      );
    SQL
  end

  def down
    # This migration is not reversible in a meaningful way
    # since we can't determine which orders had this field set by this migration
    # vs. which ones had it set by the application
  end
end