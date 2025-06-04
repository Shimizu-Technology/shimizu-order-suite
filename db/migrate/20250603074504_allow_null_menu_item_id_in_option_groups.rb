class AllowNullMenuItemIdInOptionGroups < ActiveRecord::Migration[7.2]
  def change
    # Allow menu_item_id to be null to properly support polymorphic associations
    # This enables OptionGroups to be associated with either MenuItems or FundraiserItems
    change_column_null :option_groups, :menu_item_id, true
    
    # Documentation (removed unsupported set_table_comment method)
    # Option groups can be associated with either menu_items (legacy) or optionable polymorphic association (new approach)
  end
end
