FactoryBot.define do
  factory :audit_log do
    association :restaurant
    user_id { nil }
    action { "test_action" }
    resource_type { "Order" }
    resource_id { 1 }
    details { {} }
    ip_address { "127.0.0.1" }
  end
end
