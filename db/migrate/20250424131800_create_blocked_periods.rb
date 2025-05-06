class CreateBlockedPeriods < ActiveRecord::Migration[7.0]
  def change
    create_table :blocked_periods do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.references :location, null: true, foreign_key: true
      t.references :seat_section, null: true, foreign_key: true
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.string :reason, null: false
      t.string :status, default: 'active'
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :blocked_periods, [:restaurant_id, :start_time, :end_time], name: 'idx_blocked_periods_rest_times'
    add_index :blocked_periods, [:location_id, :start_time, :end_time], name: 'idx_blocked_periods_loc_times'
    
    # Add check constraint to ensure status is valid
    execute <<-SQL
      ALTER TABLE blocked_periods
      ADD CONSTRAINT check_blocked_period_status
      CHECK (status IN ('active', 'cancelled'))
    SQL
  end
end
