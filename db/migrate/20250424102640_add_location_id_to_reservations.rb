class AddLocationIdToReservations < ActiveRecord::Migration[7.2]
  def change
    add_column :reservations, :location_id, :bigint
    add_index :reservations, :location_id
    add_foreign_key :reservations, :locations
  end
end
