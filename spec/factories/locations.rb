FactoryBot.define do
  factory :location do
    sequence(:name) { |n| "Location #{n}" }
    association :restaurant
    address { "123 Test Street" }
    phone_number { "+1234567890" }
    is_active { true }
    is_default { false }
  end
end
