class AddFirstNameLastNamePhoneToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :phone, :string

    # If you're removing the old `name` column:
    remove_column :users, :name, :string
  end
end
