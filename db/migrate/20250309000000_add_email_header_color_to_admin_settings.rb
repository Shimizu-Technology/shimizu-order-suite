class AddEmailHeaderColorToAdminSettings < ActiveRecord::Migration[7.2]
  def up
    # Add email_header_color to admin_settings for all restaurants
    Restaurant.find_each do |restaurant|
      # Get current admin_settings or initialize with empty hash
      admin_settings = restaurant.admin_settings || {}
      
      # Add email_header_color if it doesn't exist
      unless admin_settings.key?('email_header_color')
        admin_settings['email_header_color'] = '#D4AF37' # Default Hafaloha gold color
        restaurant.update_column(:admin_settings, admin_settings)
      end
    end
  end

  def down
    # This migration is not reversible in a meaningful way
    # as we don't want to remove potentially customized colors
  end
end
