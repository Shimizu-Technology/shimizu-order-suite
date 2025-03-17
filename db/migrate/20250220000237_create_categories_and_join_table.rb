# db/migrate/20250220000000_create_categories_and_join_table.rb
class CreateCategoriesAndJoinTable < ActiveRecord::Migration[7.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.integer :position, default: 0  # optional: if you want to order categories
      t.timestamps
    end

    # if you want a unique constraint so an item can't have the same category assigned twice
    create_table :menu_item_categories do |t|
      t.references :menu_item, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true

      t.timestamps
      t.index [ :menu_item_id, :category_id ], unique: true
    end
  end
end
