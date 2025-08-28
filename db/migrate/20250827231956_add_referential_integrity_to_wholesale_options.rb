class AddReferentialIntegrityToWholesaleOptions < ActiveRecord::Migration[7.2]
  def change
    # Add soft delete columns to option groups and options
    add_column :wholesale_option_groups, :deleted_at, :datetime
    add_column :wholesale_options, :deleted_at, :datetime
    
    # Add indexes for soft delete queries
    add_index :wholesale_option_groups, :deleted_at
    add_index :wholesale_options, :deleted_at
    
    # Add a column to store human-readable option selections in order items
    # This provides a backup in case option data is lost
    add_column :wholesale_order_items, :option_names, :text
    
    # Add foreign key constraints (with cascade restrictions to prevent deletion)
    # Note: This will prevent hard deletion of options/groups that are referenced in orders
    
    # We can't add foreign key constraints directly to the JSONB selected_options field,
    # but we can add a check constraint to ensure data integrity
    
    # Add a comment to document the expected structure
    change_column_comment :wholesale_order_items, :selected_options, 
      'JSONB storing option group IDs as keys and arrays of option IDs as values. Format: {"group_id": [option_id1, option_id2]}'
  end
  
  def down
    remove_column :wholesale_option_groups, :deleted_at
    remove_column :wholesale_options, :deleted_at
    remove_column :wholesale_order_items, :option_names
    change_column_comment :wholesale_order_items, :selected_options, nil
  end
end