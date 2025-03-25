class AddMenuIdToCategories < ActiveRecord::Migration[7.2]
  def change
    add_reference :categories, :menu, foreign_key: true, null: true
    add_index :categories, [:menu_id, :name], unique: true
  end
end
