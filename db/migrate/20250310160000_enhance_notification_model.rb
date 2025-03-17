class EnhanceNotificationModel < ActiveRecord::Migration[7.2]
  def change
    # Remove the reservation_id column and add resource polymorphism
    change_table :notifications do |t|
      # Add new columns only if they don't exist yet
      unless column_exists?(:notifications, :resource_type)
        t.references :resource, polymorphic: true, index: true
      end

      unless column_exists?(:notifications, :restaurant_id)
        t.references :restaurant, foreign_key: true
      end

      unless column_exists?(:notifications, :title)
        t.string :title
      end

      unless column_exists?(:notifications, :body)
        t.text :body
      end

      unless column_exists?(:notifications, :acknowledged)
        t.boolean :acknowledged, default: false
      end

      unless column_exists?(:notifications, :acknowledged_at)
        t.datetime :acknowledged_at
      end

      unless column_exists?(:notifications, :acknowledged_by_id)
        t.references :acknowledged_by, foreign_key: { to_table: :users }
      end

      # Remove reservation_id which is being replaced by polymorphic association
      t.remove :reservation_id if column_exists?(:notifications, :reservation_id)
    end

    # Add indexes for quick filtering only if it doesn't exist
    unless index_exists?(:notifications, [ :acknowledged, :notification_type, :restaurant_id ], name: 'idx_notifications_filter')
      add_index :notifications, [ :acknowledged, :notification_type, :restaurant_id ],
                name: 'idx_notifications_filter'
    end
  end
end
