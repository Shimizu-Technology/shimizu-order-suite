class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Thread-safe current restaurant accessor for multi-tenancy
  thread_mattr_accessor :current_restaurant

  # Method to scope by current restaurant if applicable
  def self.with_restaurant_scope
    if current_restaurant && column_names.include?("restaurant_id")
      where(restaurant_id: current_restaurant.id)
    else
      all
    end
  end

  # Method to apply default scope for tenant isolation
  def self.apply_default_scope
    default_scope { with_restaurant_scope }
  end
end
