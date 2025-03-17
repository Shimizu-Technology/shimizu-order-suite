class CreateMerchandiseCategories < ActiveRecord::Migration[7.2]
  def change
    # Only create the table if it doesn't already exist
    unless table_exists?(:merchandise_categories)
      create_table :merchandise_categories do |t|
        t.string :name, null: false
        t.text :description
        t.integer :display_order, default: 0
        t.boolean :active, default: true
        t.references :restaurant, null: false, foreign_key: true

        t.timestamps
      end

      add_index :merchandise_categories, [ :restaurant_id, :name ], unique: true
      add_index :merchandise_categories, [ :restaurant_id, :display_order ]
    end
  end
end
