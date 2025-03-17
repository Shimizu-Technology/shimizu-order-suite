FactoryBot.define do
  factory :order do
    association :restaurant
    user { nil } # Make user association nil by default
    items { [] }
    status { 'pending' }
    total { 0.0 }
    special_instructions { nil }
    estimated_pickup_time { nil }
    contact_name { "John Doe" }
    contact_phone { "+1234567890" }
    contact_email { "john@example.com" }
    payment_method { "credit_card" }
    transaction_id { nil }
    payment_status { "pending" }
    payment_amount { nil }

    # Add a trait for orders with users
    trait :with_user do
      association :user
    end
  end
end
