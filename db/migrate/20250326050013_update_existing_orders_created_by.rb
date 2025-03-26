class UpdateExistingOrdersCreatedBy < ActiveRecord::Migration[7.2]
  def up
    # Find the first admin user to set as the default creator for existing orders
    admin_user = User.find_by(role: 'admin')
    
    if admin_user
      # Update all existing orders that don't have a created_by_id
      execute("UPDATE orders SET created_by_id = #{admin_user.id} WHERE created_by_id IS NULL")
    end
  end
  
  def down
    # No need to revert this migration
  end
end