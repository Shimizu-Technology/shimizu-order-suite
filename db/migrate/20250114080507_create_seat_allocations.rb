class CreateSeatAllocations < ActiveRecord::Migration[7.2]
  def change
    create_table :seat_allocations do |t|
      t.references :reservation, null: false, foreign_key: true
      t.references :seat, null: false, foreign_key: true
      t.datetime :allocated_at
      t.datetime :released_at

      t.timestamps
    end
  end
end
