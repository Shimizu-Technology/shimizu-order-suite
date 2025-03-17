class AddIndexesToVipCodeRecipients < ActiveRecord::Migration[7.0]
  def change
    add_index :vip_code_recipients, :email
    add_index :vip_code_recipients, [ :vip_access_code_id, :email ]
  end
end
