class UpdateExistingUserRoles < ActiveRecord::Migration[7.2]
  def up
    # Update any existing 'employee' roles to 'staff'
    execute("UPDATE users SET role = 'staff' WHERE role = 'employee'")
  end
  
  def down
    # Revert 'staff' roles back to 'employee'
    execute("UPDATE users SET role = 'employee' WHERE role = 'staff'")
  end
end