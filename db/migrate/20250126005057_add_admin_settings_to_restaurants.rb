class AddAdminSettingsToRestaurants < ActiveRecord::Migration[7.2]
  def change
    # 1) Default reservation length
    add_column :restaurants, :default_reservation_length, :integer, default: 60, null: false

    # 2) JSON field for any future expansions
    add_column :restaurants, :admin_settings, :jsonb, default: {}, null: false
  end
end
