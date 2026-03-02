FactoryBot.define do
  factory :restaurant_counter do
    association :restaurant
    daily_order_counter { 0 }
    total_order_counter { 0 }
    last_reset_date { Date.current }
  end
end
