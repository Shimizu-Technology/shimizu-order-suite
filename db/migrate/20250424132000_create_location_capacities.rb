class CreateLocationCapacities < ActiveRecord::Migration[7.0]
  def change
    create_table :location_capacities do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.integer :total_capacity, null: false, default: 26
      t.integer :default_table_capacity, null: false, default: 4
      t.json :capacity_metadata, default: {}

      t.timestamps
    end

    add_index :location_capacities, [:restaurant_id, :location_id], unique: true
  end
end
