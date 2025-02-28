FactoryBot.define do
  factory :category do
    name { Faker::Restaurant.type }
    position { rand(0..10) }
    association :restaurant
    
    trait :appetizers do
      name { 'Appetizers' }
      position { 0 }
    end
    
    trait :entrees do
      name { 'Entrees' }
      position { 1 }
    end
    
    trait :desserts do
      name { 'Desserts' }
      position { 2 }
    end
    
    trait :drinks do
      name { 'Drinks' }
      position { 3 }
    end
    
    trait :with_menu_items do
      after(:create) do |category|
        menu = create(:menu, restaurant: category.restaurant)
        create_list(:menu_item, 3, menu: menu, categories: [category])
      end
    end
  end
end
