class ReservationCounter < ApplicationRecord
  include TenantScoped
  
  belongs_to :restaurant
  
  # Validations
  validates :monthly_counter, :total_counter, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :last_reset_date, presence: true
  validates :restaurant_id, presence: true, uniqueness: true
  
  # Find or create a counter for a restaurant
  def self.for_restaurant(restaurant_id)
    find_or_create_by(restaurant_id: restaurant_id) do |counter|
      counter.monthly_counter = 0
      counter.total_counter = 0
      counter.last_reset_date = Date.current
    end
  end
  
  # Generate a new reservation number for a restaurant
  def self.next_reservation_number(restaurant_id)
    counter = for_restaurant(restaurant_id)
    counter.generate_reservation_number
  end
  
  # Generate a new reservation number with format: [PREFIX]-R-[COUNTER]
  def generate_reservation_number
    # Check if we need to reset the monthly counter
    reset_monthly_counter_if_needed
    
    # Get restaurant prefix (first 2-3 letters of restaurant name)
    restaurant_prefix = get_restaurant_prefix
    
    # Increment counters
    self.monthly_counter += 1
    self.total_counter += 1
    
    # Format monthly counter with leading zeros (e.g., 001, 012, 123)
    counter_str = monthly_counter.to_s.rjust(3, '0')
    
    # Create the reservation number with R prefix and dashes for better readability
    reservation_number = "#{restaurant_prefix}-R-#{counter_str}"
    
    # Check if the reservation number already exists
    attempts = 0
    max_attempts = 10
    
    while Reservation.exists?(reservation_number: reservation_number) && attempts < max_attempts
      self.monthly_counter += 1
      self.total_counter += 1
      counter_str = monthly_counter.to_s.rjust(3, '0')
      reservation_number = "#{restaurant_prefix}-R-#{counter_str}"
      attempts += 1
    end
    
    # If we've tried too many times, add a unique suffix
    if attempts >= max_attempts
      timestamp_suffix = Time.now.to_i.to_s[-4..-1]
      reservation_number = "#{restaurant_prefix}-R-#{counter_str}-#{timestamp_suffix}"
    end
    
    # Save the updated counters
    save!
    
    # Return the generated reservation number
    reservation_number
  end
  
  private
  
  # Reset the monthly counter if it's a new month
  def reset_monthly_counter_if_needed
    if last_reset_date.month != Date.current.month || last_reset_date.year != Date.current.year
      self.monthly_counter = 0
      self.last_reset_date = Date.current
    end
  end
  
  # Get a 2-3 letter prefix from the restaurant name (reuse logic from RestaurantCounter)
  def get_restaurant_prefix
    name = restaurant.name.upcase
    
    if name.include?(' ')
      prefix = name.split(' ').map { |word| word[0] }.join
      prefix = prefix[0..2]
    else
      prefix = name[0..2]
    end
    
    if prefix.length < 2
      prefix = name.ljust(2, 'X')[0..1]
    end
    
    prefix
  end
end
