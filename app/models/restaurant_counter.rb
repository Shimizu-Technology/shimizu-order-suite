class RestaurantCounter < ApplicationRecord
  include TenantScoped
  
  belongs_to :restaurant
  
  # Validations
  validates :daily_order_counter, :total_order_counter, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :last_reset_date, presence: true
  validates :restaurant_id, presence: true, uniqueness: true
  
  # Find or create a counter for a restaurant
  def self.for_restaurant(restaurant_id)
    find_or_create_by(restaurant_id: restaurant_id) do |counter|
      counter.daily_order_counter = 0
      counter.total_order_counter = 0
      counter.last_reset_date = Date.current
    end
  end
  
  # Generate a new order number for a restaurant
  def self.next_order_number(restaurant_id)
    counter = for_restaurant(restaurant_id)
    counter.generate_order_number
  end
  
  # Generate a new order number with format: [PREFIX]-O-[COUNTER]
  def generate_order_number
    # Check if we need to reset the daily counter
    reset_daily_counter_if_needed
    
    # Get restaurant prefix (first 2-3 letters of restaurant name)
    restaurant_prefix = get_restaurant_prefix
    
    # Increment counters
    self.daily_order_counter += 1
    self.total_order_counter += 1
    
    # Format daily counter with leading zeros (e.g., 001, 012, 123)
    counter_str = daily_order_counter.to_s.rjust(3, '0')
    
    # Create the order number with O prefix and dashes for better readability
    order_number = "#{restaurant_prefix}-O-#{counter_str}"
    
    # Check if the order number already exists in the database
    # If it does, increment the counter and try again
    attempts = 0
    max_attempts = 10
    
    while Order.exists?(order_number: order_number) && attempts < max_attempts
      # Increment the counter and try again
      self.daily_order_counter += 1
      self.total_order_counter += 1
      counter_str = daily_order_counter.to_s.rjust(3, '0')
      order_number = "#{restaurant_prefix}-O-#{counter_str}"
      attempts += 1
    end
    
    # If we've tried too many times, add a unique suffix
    if attempts >= max_attempts
      # Add a timestamp-based suffix to ensure uniqueness
      timestamp_suffix = Time.now.to_i.to_s[-4..-1]
      order_number = "#{restaurant_prefix}-O-#{counter_str}-#{timestamp_suffix}"
    end
    
    # Save the updated counters
    save!
    
    # Return the generated order number
    order_number
  end
  
  private
  
  # Reset the daily counter if it's a new day
  def reset_daily_counter_if_needed
    if last_reset_date < Date.current
      self.daily_order_counter = 0
      self.last_reset_date = Date.current
    end
  end
  
  # Get a 2-3 letter prefix from the restaurant name
  def get_restaurant_prefix
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
end
