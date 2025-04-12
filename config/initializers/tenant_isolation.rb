# config/initializers/tenant_isolation.rb
#
# This initializer configures tenant isolation settings for the application.
# It defines which models have indirect tenant relationships and should not
# trigger warnings about missing restaurant_id columns.

# Models with indirect tenant relationships that don't need warnings
# These models implement tenant isolation through associations or custom scopes
Rails.application.config.indirect_tenant_models = %w[
  MenuItem
  Order
  Reservation
  OptionGroup
  Option
  MenuItemCategory
  MenuItemStockAudit
  OrderPayment
  OrderAcknowledgment
  Category
  SeatAllocation
  Seat
  SeatSection
  StoreCredit
  HouseAccountTransaction
  OperatingHour
  SpecialEvent
  MerchandiseVariant
  MerchandiseItem
  MerchandiseCollection
  WaitlistEntry
  Notification
  TenantEvent
  AuditLog
]

# Define relationships between models and their path to a restaurant
# This helps the tenant isolation system understand how to scope queries
Rails.application.config.tenant_relationships = {
  'MenuItem' => { through: :menu, foreign_key: 'restaurant_id' },
  'OptionGroup' => { through: [:menu_item, :menu], foreign_key: 'restaurant_id' },
  'Option' => { through: [:option_group, :menu_item, :menu], foreign_key: 'restaurant_id' },
  'MenuItemCategory' => { through: [:menu_item, :menu], foreign_key: 'restaurant_id' },
  'MenuItemStockAudit' => { through: [:menu_item, :menu], foreign_key: 'restaurant_id' },
  'Order' => { direct: true, foreign_key: 'restaurant_id' },
  'OrderPayment' => { through: :order, foreign_key: 'restaurant_id' },
  'OrderAcknowledgment' => { through: :order, foreign_key: 'restaurant_id' },
  'Reservation' => { direct: true, foreign_key: 'restaurant_id' },
  'Category' => { direct: true, foreign_key: 'restaurant_id' },
  'SeatSection' => { direct: true, foreign_key: 'restaurant_id' },
  'Seat' => { through: :seat_section, foreign_key: 'restaurant_id' },
  'SeatAllocation' => { through: [:seat, :seat_section], foreign_key: 'restaurant_id' },
  'StoreCredit' => { through: :user, foreign_key: 'restaurant_id' },
  'HouseAccountTransaction' => { through: :user, foreign_key: 'restaurant_id' },
  'OperatingHour' => { direct: true, foreign_key: 'restaurant_id' },
  'SpecialEvent' => { direct: true, foreign_key: 'restaurant_id' },
  'MerchandiseCollection' => { direct: true, foreign_key: 'restaurant_id' },
  'MerchandiseItem' => { through: :merchandise_collection, foreign_key: 'restaurant_id' },
  'MerchandiseVariant' => { through: [:merchandise_item, :merchandise_collection], foreign_key: 'restaurant_id' },
  'WaitlistEntry' => { direct: true, foreign_key: 'restaurant_id' },
  'Notification' => { through: :user, foreign_key: 'restaurant_id' },
  'TenantEvent' => { direct: true, foreign_key: 'restaurant_id' },
  'AuditLog' => { direct: true, foreign_key: 'restaurant_id' }
}
