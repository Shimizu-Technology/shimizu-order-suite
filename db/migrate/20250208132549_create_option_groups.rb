class CreateOptionGroups < ActiveRecord::Migration[7.2]
  def change
    create_table :option_groups do |t|
      t.string :name, null: false          # e.g. "Size", "Flavors", "Toppings"
      t.integer :min_select, default: 0    # min number of options required
      t.integer :max_select, default: 1    # max number of options allowed
      t.boolean :required, default: false  # must the user select from this group?
      t.references :menu_item, null: false, foreign_key: true

      t.timestamps
    end
  end
end
