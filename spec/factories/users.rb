FactoryBot.define do
  factory :user do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.email }
    password { 'password123' }
    password_confirmation { 'password123' }
    phone { Faker::PhoneNumber.cell_phone }
    role { 'customer' }
    restaurant { nil }
    
    trait :admin do
      role { 'admin' }
      association :restaurant
    end
    
    trait :with_restaurant do
      association :restaurant
    end
    
    trait :with_verified_phone do
      phone_verified { true }
    end
    
    trait :with_reset_token do
      reset_password_token { Digest::SHA256.hexdigest(SecureRandom.hex(10)) }
      reset_password_sent_at { Time.current }
    end
  end
end
