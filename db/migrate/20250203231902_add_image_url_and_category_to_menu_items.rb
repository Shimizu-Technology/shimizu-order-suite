# db/migrate/20250926002000_add_image_url_and_category_to_menu_items.rb
class AddImageUrlAndCategoryToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :image_url, :string
    add_column :menu_items, :category, :string
  end
end
