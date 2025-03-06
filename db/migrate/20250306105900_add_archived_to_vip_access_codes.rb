class AddArchivedToVipAccessCodes < ActiveRecord::Migration[7.0]
  def change
    add_column :vip_access_codes, :archived, :boolean, default: false
    add_index :vip_access_codes, :archived
  end
end
