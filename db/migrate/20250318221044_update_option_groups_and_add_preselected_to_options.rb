class UpdateOptionGroupsAndAddPreselectedToOptions < ActiveRecord::Migration[7.2]
  def up
    # Add is_preselected to options
    add_column :options, :is_preselected, :boolean, default: false, null: false
    
    # Update min_select for option groups where required=true and min_select=0
    execute <<-SQL
      UPDATE option_groups 
      SET min_select = 1 
      WHERE required = true AND min_select = 0
    SQL
    
    # Remove required column from option_groups
    remove_column :option_groups, :required
  end
  
  def down
    # Add required column back
    add_column :option_groups, :required, :boolean, default: false
    
    # Set required=true for any group with min_select > 0
    execute <<-SQL
      UPDATE option_groups
      SET required = true
      WHERE min_select > 0
    SQL
    
    # Remove is_preselected from options
    remove_column :options, :is_preselected
  end
end
