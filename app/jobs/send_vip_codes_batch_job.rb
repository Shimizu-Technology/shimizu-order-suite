class SendVipCodesBatchJob < ApplicationJob
  queue_as :default

  def perform(email_list, options = {})
    # Get the restaurant
    restaurant_id = options[:restaurant_id]
    restaurant = Restaurant.find(restaurant_id)

    # Check if we should use existing codes or generate new ones
    use_existing_codes = options[:use_existing_codes] || false
    existing_codes = options[:code_ids] || []
    
    # Check if we should create one code per batch (default to true for new codes)
    one_code_per_batch = options.fetch(:one_code_per_batch, true)

    # If using existing codes, fetch them from the database
    vip_codes = if use_existing_codes && existing_codes.present?
      VipAccessCode.where(id: existing_codes, restaurant_id: restaurant_id)
    else
      []
    end
    
    # For new codes with one_code_per_batch, create a single code for all emails
    shared_vip_code = nil
    if !use_existing_codes && one_code_per_batch
      shared_vip_code = create_vip_code(options, restaurant)
      
      # If max_uses is set, ensure it's sufficient for all recipients
      if shared_vip_code.max_uses.present? && shared_vip_code.max_uses < email_list.length
        # Update max_uses to accommodate all recipients
        shared_vip_code.update(max_uses: email_list.length)
      end
    end

    # Process each email in the batch
    email_list.each_with_index do |email, index|
      # Determine which VIP code to use for this email
      vip_code = if use_existing_codes && index < vip_codes.length
        # Use an existing code from the fetched list
        vip_codes[index]
      elsif shared_vip_code
        # Use the shared code for all recipients
        shared_vip_code
      else
        # Generate a new unique VIP code for each recipient
        create_vip_code(options, restaurant)
      end

      # Record the recipient information
      vip_code.vip_code_recipients.create!(
        email: email,
        sent_at: Time.current
      )

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
