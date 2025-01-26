# db/migrate/20250128000000_add_closed_and_times_to_special_events.rb
class AddClosedAndTimesToSpecialEvents < ActiveRecord::Migration[7.2]
  def change
    add_column :special_events, :closed, :boolean, default: false
    add_column :special_events, :start_time, :time
    add_column :special_events, :end_time, :time
  end
end
