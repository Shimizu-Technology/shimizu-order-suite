class CreateSeatSections < ActiveRecord::Migration[7.2]
  def change
    create_table :seat_sections do |t|
      t.string :name
      t.string :section_type
      t.string :orientation
      t.integer :offset_x
      t.integer :offset_y
      t.integer :capacity
      t.references :restaurant, null: false, foreign_key: true

      t.timestamps
    end
  end
end
