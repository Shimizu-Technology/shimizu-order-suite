FactoryBot.define do
  factory :menu do
    name { "#{Faker::Food.ethnic_category} Menu" }
    active { true }
    association :restaurant
    
    trait :inactive do
      active { false }
    end
    
    trait :with_items do
      after(:create) do |menu|
        create_list(:menu_item, 3, menu: menu)
      end
    end
    
    trait :with_categories do
      after(:create) do |menu|
        categories = create_list(:category, 3, restaurant: menu.restaurant)
        create_list(:menu_item, 2, menu: menu, categories: [categories.first])
        create_list(:menu_item, 2, menu: menu, categories: [categories.second])
        create_list(:menu_item, 2, menu: menu, categories: [categories.last])
      end
    end
  end
end
