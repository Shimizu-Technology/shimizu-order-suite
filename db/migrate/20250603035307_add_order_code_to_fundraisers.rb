class AddOrderCodeToFundraisers < ActiveRecord::Migration[7.2]
  def change
    add_column :fundraisers, :order_code, :string
    
    # Add an index for uniqueness scoped to restaurant_id
    add_index :fundraisers, [:restaurant_id, :order_code], unique: true, name: 'index_fundraisers_on_restaurant_id_and_order_code'
    
    # Set a default order code for existing fundraisers based on their ID
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE fundraisers
          SET order_code = CONCAT('F', id)
          WHERE order_code IS NULL
        SQL
      end
    end
  end
end
