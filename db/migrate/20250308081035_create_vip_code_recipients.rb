class CreateVipCodeRecipients < ActiveRecord::Migration[7.2]
  def change
    create_table :vip_code_recipients do |t|
      t.references :vip_access_code, null: false, foreign_key: true
      t.string :email
      t.datetime :sent_at

      t.timestamps
    end
  end
end
