class AddIsAvailableToOptions < ActiveRecord::Migration[7.2]
  def change
    add_column :options, :is_available, :boolean, default: true, null: false
    add_index :options, :is_available
  end
end
