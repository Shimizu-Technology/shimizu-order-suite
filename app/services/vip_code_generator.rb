class VipCodeGenerator
  def self.generate_codes(restaurant, count, options = {})
    codes = []
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
    codes
  end
  
  def self.generate_group_code(restaurant, options = {})
    code = new_unique_code(restaurant, options[:prefix])
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
      letters = ('A'..'Z').to_a.sample(4).join
      numbers = rand(1000..9999).to_s
      
      code = "#{prefix}-#{letters}-#{numbers}"
      
      # Make sure code is unique for this restaurant
      return code unless VipAccessCode.where(restaurant_id: restaurant.id).exists?(code: code)
    end
  end
end
