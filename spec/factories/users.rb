FactoryBot.define do
  factory :user do
    association :restaurant

    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }

    first_name { "Test" }
    last_name { "User" }

    role { "customer" }
    phone_verified { false }

    trait :admin do
      role { "admin" }
    end

    trait :with_phone do
      sequence(:phone) { |n| "+1555123#{n.to_s.rjust(4, '0')}" }
      phone_verified { true }
    end
  end
end
