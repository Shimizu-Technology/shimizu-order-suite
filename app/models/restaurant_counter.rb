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
  # Uses pessimistic locking to prevent race conditions under concurrency.
  def generate_order_number
    max_attempts = 3
    attempts = 0

    begin
      attempts += 1

      RestaurantCounter.transaction do
        # Lock the row for update to prevent concurrent reads
        locked_counter = RestaurantCounter.lock("FOR UPDATE").find(id)

        # Check if we need to reset the daily counter
        if locked_counter.last_reset_date < Date.current
          locked_counter.daily_order_counter = 0
          locked_counter.last_reset_date = Date.current
        end

        # Get restaurant prefix (first 2-3 letters of restaurant name)
        restaurant_prefix = get_restaurant_prefix

        # Increment counters
        locked_counter.daily_order_counter += 1
        locked_counter.total_order_counter += 1

        # Format daily counter with leading zeros (e.g., 001, 012, 123)
        counter_str = locked_counter.daily_order_counter.to_s.rjust(3, '0')

        # Safety check: if we've gone beyond 999, start using 4-digit numbers
        if locked_counter.daily_order_counter > 999
          counter_str = locked_counter.daily_order_counter.to_s.rjust(4, '0')
        end

        # Create the order number with O prefix and dashes for better readability
        order_number = "#{restaurant_prefix}-O-#{counter_str}"

        # If a collision still somehow exists, keep incrementing within the lock
        while Order.exists?(order_number: order_number, restaurant_id: restaurant.id)
          locked_counter.daily_order_counter += 1
          locked_counter.total_order_counter += 1
          counter_str = locked_counter.daily_order_counter.to_s.rjust(locked_counter.daily_order_counter > 999 ? 4 : 3, '0')
          order_number = "#{restaurant_prefix}-O-#{counter_str}"
        end

        # Save the updated counters atomically
        locked_counter.save!

        # Sync self with the locked values
        self.daily_order_counter = locked_counter.daily_order_counter
        self.total_order_counter = locked_counter.total_order_counter
        self.last_reset_date = locked_counter.last_reset_date

        # Return the generated order number
        return order_number
      end
    rescue ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("Order number collision (attempt #{attempts}/#{max_attempts}): #{e.message}")
      retry if attempts < max_attempts
      raise
    end
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
