class CreateReservationCounters < ActiveRecord::Migration[7.2]
  def change
    create_table :reservation_counters do |t|
      t.references :restaurant, null: false, foreign_key: true, index: { unique: true }
      t.integer :monthly_counter, default: 0, null: false
      t.integer :total_counter, default: 0, null: false
      t.date :last_reset_date, null: false

      t.timestamps
    end
    
    add_column :reservations, :reservation_number, :string
    add_index :reservations, :reservation_number, unique: true
  end
end
