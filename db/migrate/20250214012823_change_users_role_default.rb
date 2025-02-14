class ChangeUsersRoleDefault < ActiveRecord::Migration[7.0]
  def change
    change_column_default :users, :role, from: "staff", to: "customer"
  end
end
