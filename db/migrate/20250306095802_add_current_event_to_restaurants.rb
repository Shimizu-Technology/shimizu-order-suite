class AddCurrentEventToRestaurants < ActiveRecord::Migration[7.0]
  def change
    add_reference :restaurants, :current_event, foreign_key: { to_table: :special_events }, null: true
  end
end
