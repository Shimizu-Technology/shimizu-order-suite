class MovePushoverToAdminSettings < ActiveRecord::Migration[7.0]
  def up
    # First, copy existing data to admin_settings
    Restaurant.find_each do |restaurant|
      next unless restaurant.pushover_user_key.present? || 
                  restaurant.pushover_group_key.present? || 
                  restaurant.pushover_app_token.present?

      # Initialize the pushover section of admin_settings if needed
      admin_settings = restaurant.admin_settings || {}
      admin_settings["pushover"] ||= {}
      
      # Copy values
      admin_settings["pushover"]["user_key"] = restaurant.pushover_user_key if restaurant.pushover_user_key.present?
      admin_settings["pushover"]["group_key"] = restaurant.pushover_group_key if restaurant.pushover_group_key.present?
      admin_settings["pushover"]["app_token"] = restaurant.pushover_app_token if restaurant.pushover_app_token.present?
      
      # Save changes
      restaurant.update_column(:admin_settings, admin_settings)
    end
    
    # Remove the columns
    remove_index :restaurants, :pushover_user_key if index_exists?(:restaurants, :pushover_user_key)
    remove_index :restaurants, :pushover_group_key if index_exists?(:restaurants, :pushover_group_key)
    remove_column :restaurants, :pushover_user_key
    remove_column :restaurants, :pushover_group_key
    remove_column :restaurants, :pushover_app_token
  end
  
  def down
    # Add the columns back
    add_column :restaurants, :pushover_user_key, :string
    add_column :restaurants, :pushover_group_key, :string
    add_column :restaurants, :pushover_app_token, :string
    add_index :restaurants, :pushover_user_key
    add_index :restaurants, :pushover_group_key
    
    # Copy data back from admin_settings
    Restaurant.find_each do |restaurant|
      next if restaurant.admin_settings.blank? || restaurant.admin_settings["pushover"].blank?
      
      restaurant.update_columns(
        pushover_user_key: restaurant.admin_settings.dig("pushover", "user_key"),
        pushover_group_key: restaurant.admin_settings.dig("pushover", "group_key"),
        pushover_app_token: restaurant.admin_settings.dig("pushover", "app_token")
      )
    end
  end
end
