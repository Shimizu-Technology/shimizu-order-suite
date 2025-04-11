# app/models/site_setting.rb
class SiteSetting < ApplicationRecord
  # Add association with Restaurant for tenant isolation
  belongs_to :restaurant
  
  # Add default scope for tenant isolation
  default_scope { with_restaurant_scope }
  
  # Class method to scope by restaurant
  def self.with_restaurant_scope
    if ActiveRecord::Base.current_restaurant
      where(restaurant_id: ActiveRecord::Base.current_restaurant.id)
    else
      all
    end
  end
  
  # Optionally add validations if you like:
  # validates :hero_image_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  # etc.
end
