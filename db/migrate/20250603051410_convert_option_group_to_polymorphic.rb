class ConvertOptionGroupToPolymorphic < ActiveRecord::Migration[7.2]
  def up
    # Add polymorphic association columns
    add_column :option_groups, :optionable_type, :string
    add_column :option_groups, :optionable_id, :bigint
    add_index :option_groups, [:optionable_type, :optionable_id]
    
    # Migrate existing data
    execute <<-SQL
      UPDATE option_groups 
      SET optionable_type = 'MenuItem', optionable_id = menu_item_id
      WHERE menu_item_id IS NOT NULL
    SQL
    
    # Don't remove menu_item_id yet to ensure compatibility with existing code
    # We'll make a separate migration later to remove it after all code is updated
  end
  
  def down
    # Ensure we can roll back safely
    execute <<-SQL
      UPDATE option_groups 
      SET menu_item_id = optionable_id
      WHERE optionable_type = 'MenuItem' AND optionable_id IS NOT NULL
    SQL
    
    # Remove polymorphic columns
    remove_index :option_groups, [:optionable_type, :optionable_id] if index_exists?(:option_groups, [:optionable_type, :optionable_id])
    remove_column :option_groups, :optionable_type
    remove_column :option_groups, :optionable_id
  end
end
