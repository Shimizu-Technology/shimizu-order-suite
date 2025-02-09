class AddAdvanceNoticeHoursToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :advance_notice_hours, :integer, default: 0, null: false
  end
end
