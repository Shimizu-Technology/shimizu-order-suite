class CreateWaitlistEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :waitlist_entries do |t|
      t.references :restaurant, null: false, foreign_key: true
      t.string :contact_name
      t.integer :party_size
      t.datetime :check_in_time
      t.string :status

      t.timestamps
    end
  end
end
