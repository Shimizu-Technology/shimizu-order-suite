class AddCreatedByToOrders < ActiveRecord::Migration[7.2]
  def up
    # Check if the column already exists
    unless column_exists?(:orders, :created_by_id)
      add_reference :orders, :created_by, foreign_key: { to_table: :users }
    end
    
    # Check if the index already exists
    unless index_exists?(:orders, :created_by_id)
      add_index :orders, :created_by_id
    end
  end
  
  def down
    # Only remove if they exist
    if index_exists?(:orders, :created_by_id)
      remove_index :orders, :created_by_id
    end
    
    if column_exists?(:orders, :created_by_id)
      remove_reference :orders, :created_by
    end
  end
end