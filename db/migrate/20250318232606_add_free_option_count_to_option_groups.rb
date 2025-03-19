class AddFreeOptionCountToOptionGroups < ActiveRecord::Migration[7.2]
  def change
    add_column :option_groups, :free_option_count, :integer, default: 0, null: false
  end
end
