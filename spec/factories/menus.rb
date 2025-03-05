FactoryBot.define do
  factory :menu do
    sequence(:name) { |n| "Menu #{n}" }
    association :restaurant
  end
end
