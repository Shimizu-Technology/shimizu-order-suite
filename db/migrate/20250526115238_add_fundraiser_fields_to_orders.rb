class AddFundraiserFieldsToOrders < ActiveRecord::Migration[7.2]
  def change
    add_reference :orders, :fundraiser, null: true, foreign_key: true
    add_reference :orders, :fundraiser_participant, null: true, foreign_key: true
    add_column :orders, :is_fundraiser_order, :boolean, default: false
    
    # Add an index for efficient querying of fundraiser orders
    add_index :orders, :is_fundraiser_order
  end
end
