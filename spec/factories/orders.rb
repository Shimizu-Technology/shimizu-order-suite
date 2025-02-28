FactoryBot.define do
  factory :order do
    association :restaurant
    user { nil }
    items { [] }
    status { 'pending' }
    total { 0.0 }
    promo_code { nil }
    special_instructions { Faker::Lorem.sentence }
    estimated_pickup_time { Time.current + 30.minutes }
    contact_name { Faker::Name.name }
    contact_phone { Faker::PhoneNumber.cell_phone }
    contact_email { Faker::Internet.email }
    
    trait :with_user do
      association :user
    end
    
    trait :with_items do
      items do
        menu = create(:menu, restaurant: restaurant)
        menu_items = create_list(:menu_item, 3, menu: menu)
        
        menu_items.map do |item|
          {
            id: item.id,
            name: item.name,
            price: item.price,
            quantity: rand(1..3),
            special_instructions: Faker::Lorem.sentence,
            options: []
          }
        end
      end
      
      total { items.sum { |item| item[:price] * item[:quantity] } }
    end
    
    trait :completed do
      status { 'completed' }
    end
    
    trait :cancelled do
      status { 'cancelled' }
    end
    
    trait :processing do
      status { 'processing' }
    end
    
    trait :with_promo do
      after(:create) do |order|
        promo = create(:promo_code, restaurant: order.restaurant)
        order.update(promo_code: promo.code)
      end
    end
  end
end
