class SimplifyMerchandiseSystem < ActiveRecord::Migration[7.2]
  def up
    # Remove category reference from merchandise_items if it exists
    if column_exists?(:merchandise_items, :merchandise_category_id)
      remove_reference :merchandise_items, :merchandise_category
    end

    # Add second_image_url to merchandise_items if not exists
    unless column_exists?(:merchandise_items, :second_image_url)
      add_column :merchandise_items, :second_image_url, :string
    end

    # Add low_stock_threshold to merchandise_variants if not exists
    unless column_exists?(:merchandise_variants, :low_stock_threshold)
      add_column :merchandise_variants, :low_stock_threshold, :integer, default: 5
    end

    # Drop merchandise_stock_audits table if exists
    if table_exists?(:merchandise_stock_audits)
      drop_table :merchandise_stock_audits
    end

    # Drop merchandise_categories table if exists
    if table_exists?(:merchandise_categories)
      drop_table :merchandise_categories
    end
  end

  def down
    # This migration is not designed to be reversible
    raise ActiveRecord::IrreversibleMigration
  end
end