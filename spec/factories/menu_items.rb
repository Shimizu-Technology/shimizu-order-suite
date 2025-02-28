FactoryBot.define do
  factory :menu_item do
    name { Faker::Food.dish }
    description { Faker::Food.description }
    price { Faker::Commerce.price(range: 5.0..30.0) }
    available { true }
    image_url { "https://example.com/images/#{Faker::Lorem.word}.jpg" }
    category { nil }
    advance_notice_hours { 0 }
    seasonal { false }
    available_from { nil }
    available_until { nil }
    promo_label { nil }
    featured { false }
    stock_status { nil }
    status_note { nil }
    association :menu
    
    transient do
      categories { [] }
    end
    
    after(:create) do |menu_item, evaluator|
      evaluator.categories.each do |category|
        create(:menu_item_category, menu_item: menu_item, category: category)
      end
    end
    
    trait :unavailable do
      available { false }
    end
    
    trait :featured do
      featured { true }
      promo_label { 'Featured' }
    end
    
    trait :seasonal do
      seasonal { true }
      available_from { Date.current }
      available_until { Date.current + 3.months }
    end
    
    trait :with_option_groups do
      after(:create) do |menu_item|
        create_list(:option_group, 2, menu_item: menu_item)
      end
    end
  end
end
