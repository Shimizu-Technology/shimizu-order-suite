# db/migrate/20250220_migrate_single_category_to_join_table.rb
class MigrateSingleCategoryToJoinTable < ActiveRecord::Migration[7.2]
  def up
    # 1) Collect each distinct category string from the old column
    distinct_cats = MenuItem.distinct.pluck(:category).compact

    distinct_cats.each do |cat_name|
      next if cat_name.strip.blank?

      # 2) Create/find the Category by that name
      # You can adjust how you want to handle casing, etc.
      cat = Category.find_or_create_by!(name: cat_name)

      # 3) Link every MenuItem that used that old category
      MenuItem.where(category: cat_name).find_each do |item|
        MenuItemCategory.find_or_create_by!(
          menu_item_id: item.id,
          category_id: cat.id
        )
      end
    end

    # Optionally, if you want to remove the old column eventually:
    # remove_column :menu_items, :category
  end

  def down
    # Usually just a no‐op or you can remove the created joins
    # and re‐add the old column.
    # For simplicity, we’ll leave it empty.
  end
end
