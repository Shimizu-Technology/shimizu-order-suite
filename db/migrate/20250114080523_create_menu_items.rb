class CreateMenuItems < ActiveRecord::Migration[7.2]
  def change
    create_table :menu_items do |t|
      t.string :name
      t.text :description
      t.decimal :price, precision: 8, scale: 2, default: 0.0
      t.boolean :available, default: true
      t.references :menu, null: false, foreign_key: true

      t.timestamps
    end
  end
end
