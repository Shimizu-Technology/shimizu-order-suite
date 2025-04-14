class CreateLocations < ActiveRecord::Migration[7.2]
  def change
    create_table :locations do |t|
      t.references :restaurant, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :address
      t.string :phone_number
      t.boolean :is_active, default: true
      t.boolean :is_default, default: false
      t.string :email
      t.text :description

      t.timestamps
    end
    
    # Add an index to improve query performance when filtering by restaurant and is_active
    add_index :locations, [:restaurant_id, :is_active]
    
    # Add a unique index to ensure only one default location per restaurant
    add_index :locations, [:restaurant_id, :is_default], unique: true, where: "is_default = true", name: "index_locations_on_restaurant_id_and_default"
  end
end
