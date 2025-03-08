class EnsureVipCodeExistsInOrders < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:orders, :vip_code)
      add_column :orders, :vip_code, :string
    end
  end
end
