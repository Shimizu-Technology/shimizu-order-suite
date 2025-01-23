class CreateSeats < ActiveRecord::Migration[7.2]
  def change
    create_table :seats do |t|
      t.string :label
      t.integer :position_x
      t.integer :position_y
      t.string :status
      t.references :seat_section, null: false, foreign_key: true

      t.timestamps
    end
  end
end
