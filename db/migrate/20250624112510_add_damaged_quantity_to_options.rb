class AddDamagedQuantityToOptions < ActiveRecord::Migration[7.2]
  def change
    add_column :options, :damaged_quantity, :integer, default: 0
  end
end
