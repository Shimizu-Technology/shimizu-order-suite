# frozen_string_literal: true

class AddFrontendIdToNotificationTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :notification_templates, :frontend_id, :string
    
    # Update the unique index to include frontend_id
    remove_index :notification_templates, name: 'idx_notification_templates_unique'
    add_index :notification_templates, [:notification_type, :channel, :restaurant_id, :frontend_id], 
              unique: true, 
              name: 'idx_notification_templates_unique'
  end
end
