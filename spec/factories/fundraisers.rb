FactoryBot.define do
  factory :fundraiser do
    restaurant
    sequence(:name) { |n| "Fundraiser #{n}" }
    sequence(:slug) { |n| "fundraiser-#{n}" }
    description { "A test fundraiser for an organization" }
    banner_image_url { "https://example.com/banner.jpg" }
    active { true }
    featured { false }
    start_date { 1.day.ago }
    end_date { 1.week.from_now }
    
    trait :active do
      active { true }
    end
    
    trait :inactive do
      active { false }
    end
    
    trait :featured do
      featured { true }
    end
    
    trait :indefinite do
      end_date { nil }
    end
    
    trait :past do
      start_date { 2.weeks.ago }
      end_date { 1.week.ago }
    end
    
    trait :future do
      start_date { 1.week.from_now }
      end_date { 2.weeks.from_now }
    end
    
    trait :current do
      start_date { 1.day.ago }
      end_date { 1.week.from_now }
    end
  end
end
