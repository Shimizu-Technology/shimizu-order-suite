class CreateMerchandiseCollections < ActiveRecord::Migration[7.2]
  def change
    create_table :merchandise_collections do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :active, default: false
      t.references :restaurant, null: false, foreign_key: true

      t.timestamps
    end

    add_index :merchandise_collections, [ :restaurant_id, :active ]
  end
end
