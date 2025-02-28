class AddPhoneNumberToRestaurants < ActiveRecord::Migration[7.2]
  def change
    add_column :restaurants, :phone_number, :string
  end
end
