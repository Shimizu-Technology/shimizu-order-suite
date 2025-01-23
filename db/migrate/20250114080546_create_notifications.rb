class CreateNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :notifications do |t|
      t.references :reservation, null: false, foreign_key: true
      t.string :notification_type
      t.string :delivery_method
      t.datetime :scheduled_for
      t.string :status, default: "pending"

      t.timestamps
    end
  end
end
