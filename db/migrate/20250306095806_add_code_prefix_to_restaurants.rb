class AddCodePrefixToRestaurants < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:restaurants, :code_prefix)
      add_column :restaurants, :code_prefix, :string
    end
  end
end
