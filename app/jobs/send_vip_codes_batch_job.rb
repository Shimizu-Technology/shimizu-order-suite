class SendVipCodesBatchJob < ApplicationJob
  queue_as :default

  def perform(email_list, options = {})
    # Get the restaurant
    restaurant_id = options[:restaurant_id]
    restaurant = Restaurant.find(restaurant_id)
    
    # Check if we should use existing codes or generate new ones
    use_existing_codes = options[:use_existing_codes] || false
    existing_codes = options[:code_ids] || []
    
    # If using existing codes, fetch them from the database
    vip_codes = if use_existing_codes && existing_codes.present?
      VipAccessCode.where(id: existing_codes, restaurant_id: restaurant_id)
    else
      []
    end
    
    # Process each email in the batch
    email_list.each_with_index do |email, index|
      # Either use an existing code or generate a new one
      vip_code = if use_existing_codes && index < vip_codes.length
        # Use an existing code from the fetched list
        vip_codes[index]
      else
        # Generate a new VIP code
        create_vip_code(options, restaurant)
      end
      
      # Send the email with the VIP code - use deliver_now since we're already in a background job
      VipCodeMailer.vip_code_notification(email, vip_code, restaurant).deliver_now
      
      # Add a small delay to avoid overwhelming the mail server
      sleep(0.2) unless Rails.env.test?
    end
  end
  
  private
  
  def create_vip_code(options, restaurant)
    # Create a new VIP code with the provided options
    VipAccessCode.create!(
      code: generate_unique_code(options[:prefix]),
      name: options[:name] || "VIP Access",
      max_uses: options[:max_uses],
      current_uses: 0,
      is_active: true,
      restaurant: restaurant
    )
  end
  
  def generate_unique_code(prefix = nil)
    # Generate a unique code with optional prefix
    prefix = prefix.present? ? "#{prefix}-" : ""
    loop do
      # Generate a random code
      code = "#{prefix}#{SecureRandom.alphanumeric(8).upcase}"
      
      # Check if the code already exists
      break code unless VipAccessCode.exists?(code: code)
    end
  end
end
