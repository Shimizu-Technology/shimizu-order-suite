# app/models/site_setting.rb
class SiteSetting < ApplicationRecord
  belongs_to :restaurant, optional: true
  
  # Optionally add validations if you like:
  # validates :hero_image_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  # etc.
  
  # Find site settings for a specific restaurant, or global settings if not found
  def self.for_restaurant(restaurant_id)
    find_by(restaurant_id: restaurant_id) || first_or_create!
  end
end
