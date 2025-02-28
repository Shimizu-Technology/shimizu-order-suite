FactoryBot.define do
  factory :restaurant do
    name { Faker::Restaurant.name }
    address { Faker::Address.full_address }
    layout_type { ['standard', 'custom'].sample }
    time_zone { 'Pacific/Guam' }
    default_reservation_length { 60 }
    time_slot_interval { 30 }
    phone_number { Faker::PhoneNumber.phone_number }
    allowed_origins { ['http://localhost:3000', 'https://example.com'] }
    admin_settings { { 
      notifications_enabled: true,
      auto_confirm_reservations: false,
      max_party_size: 10,
      min_reservation_notice: 2
    } }
    
    trait :with_layout do
      after(:create) do |restaurant|
        layout = create(:layout, restaurant: restaurant)
        restaurant.update(current_layout: layout)
      end
    end
    
    trait :with_operating_hours do
      after(:create) do |restaurant|
        (0..6).each do |day|
          create(:operating_hour, restaurant: restaurant, day_of_week: day)
        end
      end
    end
  end
end
