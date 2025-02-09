class CreateOptions < ActiveRecord::Migration[7.2]
  def change
    create_table :options do |t|
      t.string :name, null: false                   # e.g. "Diki (Small)", "Kahuna (Large)", "Mango"
      t.decimal :additional_price, precision: 8, scale: 2, default: 0.0
      t.boolean :available, default: true
      t.references :option_group, null: false, foreign_key: true

      t.timestamps
    end
  end
end
