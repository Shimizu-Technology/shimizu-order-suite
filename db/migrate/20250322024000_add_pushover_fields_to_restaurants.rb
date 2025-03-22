class AddPushoverFieldsToRestaurants < ActiveRecord::Migration[7.0]
  def change
    add_column :restaurants, :pushover_user_key, :string
    add_column :restaurants, :pushover_group_key, :string
    add_column :restaurants, :pushover_app_token, :string
    
    # Add an index to improve query performance when looking up restaurants by Pushover keys
    add_index :restaurants, :pushover_user_key
    add_index :restaurants, :pushover_group_key
  end
end
