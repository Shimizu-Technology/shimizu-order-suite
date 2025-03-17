# db/migrate/20250127000000_create_operating_hours.rb
class CreateOperatingHours < ActiveRecord::Migration[7.0]
  def change
    create_table :operating_hours do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.integer :day_of_week, null: false  # 0=Sunday, 1=Monday, ... 6=Saturday
      t.time :open_time
      t.time :close_time
      t.boolean :closed, default: false

      t.timestamps
    end

    # Ensure each restaurant has at most 1 record for each day_of_week
    add_index :operating_hours, [ :restaurant_id, :day_of_week ], unique: true
  end
end
