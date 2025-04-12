# app/models/menu_item_category.rb
class MenuItemCategory < ApplicationRecord
  include IndirectTenantScoped
  
  # Define the path to restaurant for tenant isolation
  tenant_path through: [:menu_item, :menu], foreign_key: 'restaurant_id'
  
  belongs_to :menu_item
  belongs_to :category
end
