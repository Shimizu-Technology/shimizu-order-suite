class AddCategoryReferenceToMerchandiseItems < ActiveRecord::Migration[7.2]
  def change
    # Add category reference if it doesn't already exist
    unless column_exists?(:merchandise_items, :merchandise_category_id)
      add_reference :merchandise_items, :merchandise_category, foreign_key: true
    end

    # Add an index to improve query performance if it doesn't already exist
    unless index_exists?(:merchandise_items, [ :merchandise_category_id, :stock_status ])
      add_index :merchandise_items, [ :merchandise_category_id, :stock_status ],
                name: 'idx_merch_items_on_category_and_stock_status'
    end
  end
end
