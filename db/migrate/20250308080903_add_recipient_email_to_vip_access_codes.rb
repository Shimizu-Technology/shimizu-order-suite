class AddRecipientEmailToVipAccessCodes < ActiveRecord::Migration[7.2]
  def change
    add_column :vip_access_codes, :recipient_email, :string
  end
end
