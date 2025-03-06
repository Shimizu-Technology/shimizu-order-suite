class AddCurrentEventToRestaurants < ActiveRecord::Migration[7.0]
  def change
    add_reference :restaurants, :current_event, foreign_key: { to_table: :special_events }, null: true
    add_column :restaurants, :vip_enabled, :boolean, default: false
    add_column :restaurants, :code_prefix, :string
  end
end
