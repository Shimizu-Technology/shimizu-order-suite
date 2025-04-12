FactoryBot.define do
  factory :restaurant_counter do
    restaurant { nil }
    daily_order_counter { 1 }
    total_order_counter { 1 }
    last_reset_date { "2025-04-13" }
  end
end
