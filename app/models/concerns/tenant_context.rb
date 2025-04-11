# app/models/concerns/tenant_context.rb
#
# This concern adds thread-local storage for the current tenant context
# to ActiveRecord::Base. It's used by the TenantIsolation concern to
# maintain tenant context throughout a request.
#
module TenantContext
  extend ActiveSupport::Concern

  class_methods do
    # Get the current restaurant (tenant) for this thread
    def current_restaurant
      Thread.current[:current_restaurant]
    end

    # Set the current restaurant (tenant) for this thread
    def current_restaurant=(restaurant)
      Thread.current[:current_restaurant] = restaurant
    end
  end
end

# Extend ActiveRecord::Base with the TenantContext concern
ActiveRecord::Base.include TenantContext
