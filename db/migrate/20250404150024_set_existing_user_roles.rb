class SetExistingUserRoles < ActiveRecord::Migration[7.2]
  def up
    # Add default value for new users
    change_column_default :users, :role, "customer"
    
    # Set any nil roles to 'customer'
    execute <<-SQL
      UPDATE users
      SET role = 'customer'
      WHERE role IS NULL
    SQL
    
    # Set existing admins to 'super_admin' (we'll manually demote some to 'admin' or 'staff' later)
    execute <<-SQL
      UPDATE users
      SET role = 'super_admin'
      WHERE role = 'admin'
    SQL
    
    # Ensure all other users are set to 'customer'
    execute <<-SQL
      UPDATE users
      SET role = 'customer'
      WHERE role NOT IN ('super_admin', 'admin', 'staff', 'customer')
    SQL
  end
  
  def down
    # Revert admins back to 'admin'
    execute <<-SQL
      UPDATE users
      SET role = 'admin'
      WHERE role IN ('super_admin', 'admin', 'staff')
    SQL
    
    # Reset default
    change_column_default :users, :role, nil
  end
end
