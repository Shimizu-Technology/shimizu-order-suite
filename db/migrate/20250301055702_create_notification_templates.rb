# frozen_string_literal: true

class CreateNotificationTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :notification_templates do |t|
      t.references :restaurant, null: true, foreign_key: true
      t.string :notification_type, null: false
      t.string :channel, null: false
      t.string :subject
      t.text :content, null: false
      t.string :sender_name
      t.boolean :active, default: true

      t.timestamps
    end

    # Add a unique constraint to ensure only one template per type/channel/restaurant
    add_index :notification_templates, [:notification_type, :channel, :restaurant_id], 
              unique: true, 
              name: 'idx_notification_templates_unique'
  end
end
