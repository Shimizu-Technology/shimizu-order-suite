class CreateWholesaleFundraiserCounters < ActiveRecord::Migration[7.2]
  def change
    create_table :wholesale_fundraiser_counters do |t|
      t.references :fundraiser, null: false, foreign_key: { to_table: :wholesale_fundraisers }
      t.integer :counter, null: false, default: 0
      t.date :last_reset_date, null: false

      t.timestamps
    end
  end
end
