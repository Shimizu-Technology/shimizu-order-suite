class Wholesale::FundraiserCounter < ApplicationRecord
  belongs_to :fundraiser, class_name: 'Wholesale::Fundraiser'
  
  # Validations
  validates :counter, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :last_reset_date, presence: true
  validates :fundraiser_id, presence: true, uniqueness: true
  
  # Find or create a counter for a fundraiser
  def self.for_fundraiser(fundraiser_id)
    find_or_create_by(fundraiser_id: fundraiser_id) do |counter|
      counter.counter = 0
      counter.last_reset_date = Date.current
    end
  end
  
  # Generate a new order number for a fundraiser
  def self.next_order_number(fundraiser_id)
    counter_record = for_fundraiser(fundraiser_id)
    counter_record.generate_order_number
  end
  
  # Generate a new order number with format: [RESTAURANT_PREFIX]-[FUNDRAISER_PREFIX]-[COUNTER]
  def generate_order_number
    # Check if we need to reset the daily counter (optional - you can remove this if you want continuous numbering)
    reset_daily_counter_if_needed
    
    # Get restaurant and fundraiser prefixes
    restaurant_prefix = get_restaurant_prefix
    fundraiser_prefix = get_fundraiser_prefix
    
    # Increment counter
    self.counter += 1
    
    # Format counter with leading zeros (e.g., 001, 012, 123)
    counter_str = counter.to_s.rjust(3, '0')
    
    # Create the order number using slug: HAF-CSGSTTECH-001 or HAF-TECHCLUB-001
    order_number = "#{restaurant_prefix}-#{fundraiser_prefix}-#{counter_str}"
    
    # Check if the order number already exists in the database
    # If it does, keep incrementing the counter until we find a unique one
    while Wholesale::Order.exists?(order_number: order_number)
      self.counter += 1
      counter_str = counter.to_s.rjust(3, '0')
      order_number = "#{restaurant_prefix}-#{fundraiser_prefix}-#{counter_str}"
      
      # Safety check: if we've gone beyond 999, start using 4-digit numbers
      if counter > 999
        counter_str = counter.to_s.rjust(4, '0')
        order_number = "#{restaurant_prefix}-#{fundraiser_prefix}-#{counter_str}"
      end
    end
    
    # Save the updated counter
    save!
    
    # Return the generated order number
    order_number
  end
  
  private
  
  # Reset the daily counter if it's a new day (optional - remove if you want continuous numbering)
  def reset_daily_counter_if_needed
    if last_reset_date < Date.current
      self.counter = 0
      self.last_reset_date = Date.current
    end
  end
  
  # Get restaurant prefix (reuse logic from RestaurantCounter)
  def get_restaurant_prefix
    restaurant = fundraiser.restaurant
    name = restaurant.name.upcase
    
    # Try to create a meaningful prefix from the restaurant name
    if name.include?(' ')
      # If name has multiple words, use first letter of each word
      prefix = name.split(' ').map { |word| word[0] }.join
      # Limit to 3 characters
      prefix = prefix[0..2]
    else
      # For single word names, use first 3 letters
      prefix = name[0..2]
    end
    
    # Ensure we have at least 2 characters
    if prefix.length < 2
      prefix = name.ljust(2, 'X')[0..1]
    end
    
    prefix
  end
  
  # Get fundraiser prefix from fundraiser slug
  def get_fundraiser_prefix
    # Use the slug directly as it's already designed to be short and unique
    slug = fundraiser.slug.upcase
    
    # Remove any hyphens for cleaner order numbers
    prefix = slug.gsub('-', '')
    
    # Limit to reasonable length (max 8 characters to keep order numbers manageable)
    prefix = prefix[0..7] if prefix.length > 8
    
    # Ensure we have at least 2 characters (fallback, but should never happen with valid slugs)
    if prefix.length < 2
      prefix = slug.ljust(2, 'X')[0..1]
    end
    
    prefix
  end
end
