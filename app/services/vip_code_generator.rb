class VipCodeGenerator
  def self.generate_codes(restaurant, count, options = {})
    codes = []
    
    # Handle custom codes list
    if options[:custom_codes].present?
      custom_codes_list = parse_custom_codes(options[:custom_codes])
      
      # Only create up to the requested count, using custom codes
      codes_to_create = [count, custom_codes_list.length].min
      
      custom_codes_list.first(codes_to_create).each do |custom_code|
        code = validate_and_get_unique_code(restaurant, custom_code.strip)
        
        # Create the VIP code with or without max_uses
        attributes = {
          code: code,
          name: options[:name] || "Custom VIP",
          current_uses: 0,
          is_active: true,
          special_event_id: options[:special_event_id],
          group_id: options[:group_id]
        }

        # Only add max_uses if it's provided and not nil
        attributes[:max_uses] = options[:max_uses] if options[:max_uses].present?

        codes << restaurant.vip_access_codes.create!(attributes)
      end
    else
      # Original logic for generated codes
      count.times do
        code = new_unique_code(restaurant, options[:prefix])

        # Create the VIP code with or without max_uses
        attributes = {
          code: code,
          name: options[:name] || "VIP Access",
          current_uses: 0,
          is_active: true,
          special_event_id: options[:special_event_id],
          group_id: options[:group_id]
        }

        # Only add max_uses if it's provided and not nil
        attributes[:max_uses] = options[:max_uses] if options[:max_uses].present?

        codes << restaurant.vip_access_codes.create!(attributes)
      end
    end
    
    codes
  end

  def self.generate_group_code(restaurant, options = {})
    # Handle custom code for group
    if options[:custom_code].present?
      code = validate_and_get_unique_code(restaurant, options[:custom_code].strip)
    else
      code = new_unique_code(restaurant, options[:prefix])
    end
    
    restaurant.vip_access_codes.create!(
      code: code,
      name: options[:name] || "Group VIP Access",
      max_uses: options[:max_uses],
      current_uses: 0,
      is_active: true,
      special_event_id: options[:special_event_id],
      group_id: SecureRandom.uuid
    )
  end

  private

  def self.new_unique_code(restaurant, custom_prefix = nil)
    loop do
      prefix = custom_prefix || restaurant.code_prefix || "VIP"
      letters = ("A".."Z").to_a.sample(4).join
      numbers = rand(1000..9999).to_s

      code = "#{prefix}-#{letters}-#{numbers}"

      # Make sure code is unique for this restaurant
      return code unless VipAccessCode.where(restaurant_id: restaurant.id).exists?(code: code)
    end
  end
  
  def self.validate_and_get_unique_code(restaurant, custom_code)
    # Basic validation
    raise ArgumentError, "Custom code cannot be blank" if custom_code.blank?
    raise ArgumentError, "Custom code is too long (maximum 50 characters)" if custom_code.length > 50
    raise ArgumentError, "Custom code contains invalid characters" unless custom_code.match?(/\A[A-Za-z0-9\-_]+\z/)
    
    # Check uniqueness
    if VipAccessCode.where(restaurant_id: restaurant.id).exists?(code: custom_code)
      raise ArgumentError, "Custom code '#{custom_code}' already exists"
    end
    
    custom_code
  end
  
  def self.parse_custom_codes(custom_codes_input)
    # Handle both string input and array input
    if custom_codes_input.is_a?(String)
      # Split by commas, semicolons, or new lines and clean up
      custom_codes_input.split(/[,;\n\r]+/).map(&:strip).reject(&:blank?)
    elsif custom_codes_input.is_a?(Array)
      custom_codes_input.map(&:to_s).map(&:strip).reject(&:blank?)
    else
      []
    end
  end
end
