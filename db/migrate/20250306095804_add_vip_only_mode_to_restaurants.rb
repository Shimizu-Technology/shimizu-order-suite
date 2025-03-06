class AddVipOnlyModeToRestaurants < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:restaurants, :vip_only_mode)
      add_column :restaurants, :vip_only_mode, :boolean, default: false
    end
  end
end
