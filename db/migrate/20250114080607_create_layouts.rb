class CreateLayouts < ActiveRecord::Migration[7.2]
  def change
    create_table :layouts do |t|
      t.string :name
      t.references :restaurant, null: false, foreign_key: true
      t.jsonb :sections_data

      t.timestamps
    end
  end
end
