class AddPromoLabelToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :promo_label, :string
  end
end
