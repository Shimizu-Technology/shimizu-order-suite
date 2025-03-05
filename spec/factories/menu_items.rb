FactoryBot.define do
  factory :menu_item do
    name { "Test Menu Item" }
    description { "A delicious test menu item" }
    price { 10.99 }
    available { true }
    advance_notice_hours { 0 }
    seasonal { false }
    featured { false }
    stock_status { :in_stock }
    association :menu

    trait :with_option_groups do
      after(:create) do |menu_item|
        create(:option_group, menu_item: menu_item)
      end
    end

    trait :with_categories do
      after(:create) do |menu_item|
        category = create(:category, menu: menu_item.menu)
        create(:menu_item_category, menu_item: menu_item, category: category)
      end
    end

    trait :seasonal do
      seasonal { true }
      available_from { Date.current - 1.month }
      available_until { Date.current + 1.month }
    end

    trait :featured do
      featured { true }
    end

    trait :out_of_stock do
      stock_status { :out_of_stock }
      status_note { "Sold out for today" }
    end

    trait :low_stock do
      stock_status { :low_stock }
      status_note { "Only a few left" }
    end
  end
end
