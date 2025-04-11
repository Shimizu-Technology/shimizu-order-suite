class AddMultiTenantConstraints < ActiveRecord::Migration[7.2]
  def change
    # Add NOT NULL constraints to restaurant_id columns where appropriate
    # Note: We're excluding User model since super_admin users don't have a restaurant_id
    
    # Menu model
    if column_exists?(:menus, :restaurant_id)
      change_column_null :menus, :restaurant_id, false unless column_null?(:menus, :restaurant_id) == false
      add_foreign_key_if_not_exists :menus, :restaurants, on_delete: :cascade
    end
    
    # Order model
    if column_exists?(:orders, :restaurant_id)
      change_column_null :orders, :restaurant_id, false unless column_null?(:orders, :restaurant_id) == false
      add_foreign_key_if_not_exists :orders, :restaurants, on_delete: :cascade
    end
    
    # Reservation model
    if column_exists?(:reservations, :restaurant_id)
      change_column_null :reservations, :restaurant_id, false unless column_null?(:reservations, :restaurant_id) == false
      add_foreign_key_if_not_exists :reservations, :restaurants, on_delete: :cascade
    end
    
    # Skip Staff member model as we're handling it in a separate migration
    
    # Merchandise collection model
    if column_exists?(:merchandise_collections, :restaurant_id)
      change_column_null :merchandise_collections, :restaurant_id, false unless column_null?(:merchandise_collections, :restaurant_id) == false
      add_foreign_key_if_not_exists :merchandise_collections, :restaurants, on_delete: :cascade
    end
    
    # Notification model
    if column_exists?(:notifications, :restaurant_id)
      change_column_null :notifications, :restaurant_id, false unless column_null?(:notifications, :restaurant_id) == false
      add_foreign_key_if_not_exists :notifications, :restaurants, on_delete: :cascade
    end
    
    # Push subscription model
    if column_exists?(:push_subscriptions, :restaurant_id)
      change_column_null :push_subscriptions, :restaurant_id, false unless column_null?(:push_subscriptions, :restaurant_id) == false
      add_foreign_key_if_not_exists :push_subscriptions, :restaurants, on_delete: :cascade
    end
    
    # Promo code model
    if column_exists?(:promo_codes, :restaurant_id)
      change_column_null :promo_codes, :restaurant_id, false unless column_null?(:promo_codes, :restaurant_id) == false
      add_foreign_key_if_not_exists :promo_codes, :restaurants, on_delete: :cascade
    end
    
    # VIP access code model
    if column_exists?(:vip_access_codes, :restaurant_id)
      change_column_null :vip_access_codes, :restaurant_id, false unless column_null?(:vip_access_codes, :restaurant_id) == false
      add_foreign_key_if_not_exists :vip_access_codes, :restaurants, on_delete: :cascade
    end
    
    # Add database-level CHECK constraint to ensure non-super_admin users have a restaurant_id
    unless constraint_exists?('users', 'users_restaurant_id_check')
      execute <<-SQL
        ALTER TABLE users
        ADD CONSTRAINT users_restaurant_id_check
        CHECK (
          (role = 'super_admin') OR
          (restaurant_id IS NOT NULL)
        );
      SQL
    end
  end
  
  def down
    # Remove foreign key constraints
    remove_foreign_key :menus, :restaurants if foreign_key_exists?(:menus, :restaurants)
    remove_foreign_key :orders, :restaurants if foreign_key_exists?(:orders, :restaurants)
    remove_foreign_key :reservations, :restaurants if foreign_key_exists?(:reservations, :restaurants)
    remove_foreign_key :staff_members, :restaurants if foreign_key_exists?(:staff_members, :restaurants)
    remove_foreign_key :merchandise_collections, :restaurants if foreign_key_exists?(:merchandise_collections, :restaurants)
    remove_foreign_key :notifications, :restaurants if foreign_key_exists?(:notifications, :restaurants)
    remove_foreign_key :push_subscriptions, :restaurants if foreign_key_exists?(:push_subscriptions, :restaurants)
    remove_foreign_key :promo_codes, :restaurants if foreign_key_exists?(:promo_codes, :restaurants)
    remove_foreign_key :vip_access_codes, :restaurants if foreign_key_exists?(:vip_access_codes, :restaurants)
    
    # Remove CHECK constraint
    if constraint_exists?('users', 'users_restaurant_id_check')
      execute "ALTER TABLE users DROP CONSTRAINT users_restaurant_id_check;"
    end
  end
  
  private
  
  def column_null?(table, column)
    connection.columns(table).find { |c| c.name == column.to_s }&.null
  end
  
  def add_foreign_key_if_not_exists(from_table, to_table, options = {})
    return if foreign_key_exists?(from_table, to_table)
    add_foreign_key(from_table, to_table, options)
  end
  
  def foreign_key_exists?(from_table, to_table)
    foreign_keys = connection.foreign_keys(from_table)
    foreign_keys.any? { |fk| fk.to_table.to_s == to_table.to_s }
  end
  
  def constraint_exists?(table, constraint_name)
    query = <<-SQL
      SELECT 1 FROM pg_constraint
      JOIN pg_class ON pg_constraint.conrelid = pg_class.oid
      JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
      WHERE pg_class.relname = '#{table}'
      AND pg_constraint.conname = '#{constraint_name}'
    SQL
    
    connection.select_value(query).present?
  end
  
  def column_exists?(table, column)
    return false unless table_exists?(table)
    connection.columns(table).any? { |c| c.name == column.to_s }
  end
  
  def table_exists?(table)
    connection.tables.include?(table.to_s)
  end
  
  def down
    # Remove foreign key constraints
    remove_foreign_key :menus, :restaurants if foreign_key_exists?(:menus, :restaurants)
    remove_foreign_key :orders, :restaurants if foreign_key_exists?(:orders, :restaurants)
    remove_foreign_key :reservations, :restaurants if foreign_key_exists?(:reservations, :restaurants)
    remove_foreign_key :staff_members, :restaurants if foreign_key_exists?(:staff_members, :restaurants)
    remove_foreign_key :merchandise_collections, :restaurants if foreign_key_exists?(:merchandise_collections, :restaurants)
    remove_foreign_key :notifications, :restaurants if foreign_key_exists?(:notifications, :restaurants)
    remove_foreign_key :push_subscriptions, :restaurants if foreign_key_exists?(:push_subscriptions, :restaurants)
    remove_foreign_key :promo_codes, :restaurants if foreign_key_exists?(:promo_codes, :restaurants)
    remove_foreign_key :vip_access_codes, :restaurants if foreign_key_exists?(:vip_access_codes, :restaurants)
    
    # Remove CHECK constraint
    execute <<-SQL
      ALTER TABLE users
      DROP CONSTRAINT IF EXISTS users_restaurant_id_check;
    SQL
    
    # Note: We're not removing the NOT NULL constraints to avoid potential data issues
  end
end
