FactoryBot.define do
  factory :option do
    name { Faker::Food.ingredient }
    additional_price { [0, 0.5, 1.0, 1.5, 2.0].sample }
    available { true }
    association :option_group
    
    trait :unavailable do
      available { false }
    end
    
    trait :free do
      additional_price { 0 }
    end
    
    trait :premium do
      additional_price { 3.0 }
      name { "Premium #{Faker::Food.ingredient}" }
    end
  end
end
