class CreateOptionStockAudits < ActiveRecord::Migration[7.2]
  def change
    create_table :option_stock_audits do |t|
      t.references :option, null: false, foreign_key: true, index: true
      t.references :user, null: true, foreign_key: true, index: true
      t.references :order, null: true, foreign_key: true, index: true
      
      t.integer :previous_quantity, null: false
      t.integer :new_quantity, null: false
      t.text :reason, null: false
      
      t.timestamps
    end
    
    # Add indexes for common queries
    add_index :option_stock_audits, :created_at
    add_index :option_stock_audits, [:option_id, :created_at]
  end
end 