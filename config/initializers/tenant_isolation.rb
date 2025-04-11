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
]
