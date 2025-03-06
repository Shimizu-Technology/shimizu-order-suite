FactoryBot.define do
  factory :vip_access_code do
    association :special_event
    association :restaurant
    
    sequence(:code) { |n| "VIP-TEST-#{n.to_s.rjust(4, '0')}" }
    name { "Test VIP Code" }
    max_uses { nil }
    current_uses { 0 }
    expires_at { nil }
    is_active { true }
    user { nil }
    group_id { nil }
    
    trait :individual do
      max_uses { 1 }
      name { "Individual VIP Code" }
    end
    
    trait :group do
      max_uses { 10 }
      name { "Group VIP Code" }
      group_id { SecureRandom.uuid }
    end
    
    trait :expired do
      expires_at { 1.day.ago }
    end
    
    trait :inactive do
      is_active { false }
    end
    
    trait :used do
      current_uses { max_uses || 1 }
    end
  end
end
