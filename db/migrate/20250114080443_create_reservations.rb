class CreateReservations < ActiveRecord::Migration[7.2]
  def change
    create_table :reservations do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.datetime :start_time
      t.datetime :end_time
      t.integer :party_size
      t.string :contact_name
      t.string :contact_phone
      t.string :contact_email
      t.decimal :deposit_amount
      t.string :reservation_source
      t.text :special_requests
      t.string :status

      t.timestamps
    end
  end
end
