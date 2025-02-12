# db/migrate/20250213_add_auth0_sub_to_users.rb
class AddAuth0SubToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :auth0_sub, :string
    add_index  :users, :auth0_sub, unique: true
  end
end
