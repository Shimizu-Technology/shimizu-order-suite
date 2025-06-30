class CreateOptionStockAudits < ActiveRecord::Migration[7.2]
  def change
    create_table :option_stock_audits do |t|
      t.references :option, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :order, null: true, foreign_key: true
      t.integer :previous_quantity, null: false
      t.integer :new_quantity, null: false
      t.string :reason

      t.timestamps
    end

    # Add indexes for performance (only ones not automatically created by references)
    add_index :option_stock_audits, :created_at
  end
end
