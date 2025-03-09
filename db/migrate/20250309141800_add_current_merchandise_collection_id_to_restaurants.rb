class AddCurrentMerchandiseCollectionIdToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_reference :restaurants, :current_merchandise_collection, foreign_key: { to_table: :merchandise_collections }, null: true
  end
end
