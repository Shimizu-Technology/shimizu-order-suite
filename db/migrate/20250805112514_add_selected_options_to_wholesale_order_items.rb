class AddSelectedOptionsToWholesaleOrderItems < ActiveRecord::Migration[7.2]
  def change
    add_column :wholesale_order_items, :selected_options, :jsonb, default: {}
    add_index :wholesale_order_items, :selected_options, using: :gin
  end
end
