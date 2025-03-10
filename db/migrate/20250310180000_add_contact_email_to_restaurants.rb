class AddContactEmailToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :contact_email, :string
  end
end
