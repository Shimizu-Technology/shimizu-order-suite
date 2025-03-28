class CreateOptionStockAudits < ActiveRecord::Migration[7.2]
  def change
    create_table :option_stock_audits do |t|
      t.references :option, null: false, foreign_key: true
      t.integer :previous_quantity
      t.integer :new_quantity
      t.string :reason
      t.references :user, foreign_key: true
      t.references :order, foreign_key: true

      t.timestamps
    end
  end
end