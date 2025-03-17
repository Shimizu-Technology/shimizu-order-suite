# db/migrate/20250127000001_create_special_events.rb
class CreateSpecialEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :special_events do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.date :event_date, null: false

      # If you want to block the entire day for a single booking:
      t.boolean :exclusive_booking, default: false

      # If you want to limit capacity or any other logic:
      t.integer :max_capacity, default: 0  # 0 => unused, or interpret however you want

      t.string :description
      t.timestamps
    end

    add_index :special_events, [ :restaurant_id, :event_date ], unique: true
  end
end
