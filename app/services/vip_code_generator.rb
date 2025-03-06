# app/services/vip_code_generator.rb
class VipCodeGenerator
  def self.generate_individual_codes(special_event, count, options = {})
    codes = []
    count.times do
      code = new_unique_code(special_event.code_prefix)
      codes << special_event.vip_access_codes.create!(
        code: code,
        name: options[:name] || "Individual VIP",
        max_uses: 1,
        current_uses: 0,
        is_active: true,
        restaurant_id: special_event.restaurant_id
      )
    end
    codes
  end
  
  def self.generate_group_code(special_event, options = {})
    code = new_unique_code(special_event.code_prefix)
    special_event.vip_access_codes.create!(
      code: code,
      name: options[:name] || "Group VIP",
      max_uses: options[:max_uses],
      current_uses: 0,
      is_active: true,
      restaurant_id: special_event.restaurant_id,
      group_id: SecureRandom.uuid
    )
  end
  
  # Generate codes directly for a restaurant (not tied to an event)
  def self.generate_codes_for_restaurant(restaurant, count, options = {})
    codes = []
    count.times do
      code = new_unique_code(restaurant.code_prefix)
      codes << restaurant.vip_access_codes.create!(
        code: code,
        name: options[:name] || "Restaurant VIP",
        max_uses: options[:max_uses] || 1,
        current_uses: 0,
        is_active: true
      )
    end
    codes
  end
  
  private
  
  def self.new_unique_code(prefix = nil)
    loop do
      prefix ||= "VIP"
      letters = ('A'..'Z').to_a.sample(4).join
      numbers = rand(1000..9999).to_s
      
      code = "#{prefix}-#{letters}-#{numbers}"
      
      return code unless VipAccessCode.exists?(code: code)
    end
  end
end
