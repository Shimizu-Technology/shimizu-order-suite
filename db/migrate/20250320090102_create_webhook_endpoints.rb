class CreateWebhookEndpoints < ActiveRecord::Migration[7.2]
  def change
    create_table :webhook_endpoints do |t|
      t.string :url
      t.string :description
      t.string :secret
      t.boolean :active, default: true
      t.references :restaurant, null: false, foreign_key: true
      t.string :event_types, array: true, default: []

      t.timestamps
    end
    
    # The restaurant_id index is already created by t.references :restaurant above
    add_index :webhook_endpoints, :event_types, using: 'gin'
  end
end
