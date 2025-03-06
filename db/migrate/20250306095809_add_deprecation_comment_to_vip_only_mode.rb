class AddDeprecationCommentToVipOnlyMode < ActiveRecord::Migration[7.0]
  def up
    # Add a comment to the vip_only_mode column indicating it's deprecated
    execute <<-SQL
      COMMENT ON COLUMN restaurants.vip_only_mode IS 'DEPRECATED: Use vip_enabled instead. This column will be removed in a future version.';
    SQL
  end

  def down
    # Remove the comment
    execute <<-SQL
      COMMENT ON COLUMN restaurants.vip_only_mode IS NULL;
    SQL
  end
end
