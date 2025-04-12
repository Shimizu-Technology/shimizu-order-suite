class AddOrderNumberToHouseAccountTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :house_account_transactions, :order_number, :string
  end
end
