class AddCurrentMenuIdToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_reference :restaurants, :current_menu, foreign_key: { to_table: :menus }, null: true
  end
end
