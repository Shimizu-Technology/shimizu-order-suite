class AddFeaturedToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :featured, :boolean
  end
end
