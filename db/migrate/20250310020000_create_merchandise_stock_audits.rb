class CreateMerchandiseStockAudits < ActiveRecord::Migration[7.2]
  def change
    # Skip if the table already exists
    unless table_exists?(:merchandise_stock_audits)
      create_table :merchandise_stock_audits do |t|
        t.references :merchandise_variant, null: false, foreign_key: true
        t.integer :previous_quantity, null: false
        t.integer :new_quantity, null: false
        t.string :reason
        t.references :user, foreign_key: true
        t.references :order, foreign_key: true

        t.timestamps
      end

      add_index :merchandise_stock_audits, :created_at
    end
  end
end
