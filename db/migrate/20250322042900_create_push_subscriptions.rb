class CreatePushSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :push_subscriptions do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :user_agent
      t.boolean :active, default: true
      
      t.timestamps
      
      t.index [:restaurant_id, :endpoint], unique: true
    end
  end
end
