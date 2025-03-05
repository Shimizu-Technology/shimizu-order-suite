FactoryBot.define do
  factory :option do
    sequence(:name) { |n| "Option #{n}" }
    association :option_group
    additional_price { 0.0 }
    available { true }
  end
end
