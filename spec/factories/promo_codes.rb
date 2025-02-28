FactoryBot.define do
  factory :promo_code do
    code { Faker::Alphanumeric.alpha(number: 8).upcase }
    discount_percent { [5, 10, 15, 20, 25].sample }
    valid_from { Time.current - 1.day }
    valid_until { Time.current + 30.days }
    max_uses { 100 }
    current_uses { 0 }
    association :restaurant
    
    trait :expired do
      valid_from { Time.current - 60.days }
      valid_until { Time.current - 30.days }
    end
    
    trait :future do
      valid_from { Time.current + 10.days }
      valid_until { Time.current + 40.days }
    end
    
    trait :limited do
      max_uses { 10 }
    end
    
    trait :used do
      current_uses { 5 }
    end
    
    trait :fully_used do
      max_uses { 10 }
      current_uses { 10 }
    end
    
    trait :high_discount do
      discount_percent { 50 }
    end
  end
end
