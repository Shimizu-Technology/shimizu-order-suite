class CopyVipOnlyModeToVipEnabled < ActiveRecord::Migration[7.0]
  def up
    # Copy values from vip_only_mode to vip_enabled for all restaurants
    execute <<-SQL
      UPDATE restaurants 
      SET vip_enabled = vip_only_mode
      WHERE vip_only_mode IS NOT NULL
    SQL
  end

  def down
    # Copy values from vip_enabled back to vip_only_mode
    execute <<-SQL
      UPDATE restaurants 
      SET vip_only_mode = vip_enabled
      WHERE vip_enabled IS NOT NULL
    SQL
  end
end
