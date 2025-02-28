FactoryBot.define do
  factory :menu_item_category do
    association :menu_item
    association :category
  end
end
