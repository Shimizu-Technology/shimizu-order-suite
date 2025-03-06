class AddVipFieldsToSpecialEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :special_events, :vip_only_checkout, :boolean, default: false
    add_column :special_events, :code_prefix, :string
  end
end
