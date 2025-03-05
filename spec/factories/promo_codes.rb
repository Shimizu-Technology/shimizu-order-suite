FactoryBot.define do
  factory :promo_code do
    sequence(:code) { |n| "PROMO#{n}" }
    discount_percent { 10 }
    valid_from { Time.current }
    valid_until { 1.month.from_now }
    max_uses { 100 }
    current_uses { 0 }
    association :restaurant
  end
end
