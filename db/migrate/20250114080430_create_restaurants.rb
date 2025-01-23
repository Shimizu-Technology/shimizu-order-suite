class CreateRestaurants < ActiveRecord::Migration[7.2]
  def change
    create_table :restaurants do |t|
      t.string :name
      t.string :address
      t.string :opening_hours
      t.string :layout_type

      t.timestamps
    end
  end
end
