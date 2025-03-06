class AddVipEnabledFlagToRestaurants < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:restaurants, :vip_enabled)
      add_column :restaurants, :vip_enabled, :boolean, default: false
    end
  end
end
