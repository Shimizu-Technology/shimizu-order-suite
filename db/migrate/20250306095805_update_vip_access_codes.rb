class UpdateVipAccessCodes < ActiveRecord::Migration[7.0]
  def change
    # Make special_event_id optional
    change_column_null :vip_access_codes, :special_event_id, true
  end
end
