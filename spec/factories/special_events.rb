FactoryBot.define do
  factory :special_event do
    association :restaurant
    event_date { Date.current + 10.days }
    exclusive_booking { false }
    max_capacity { 100 }
    description { Faker::Lorem.sentence }
    closed { false }
    start_time { Time.parse('18:00:00') }
    end_time { Time.parse('22:00:00') }
    
    trait :closed_day do
      closed { true }
      description { "Closed for #{Faker::Lorem.word}" }
    end
    
    trait :exclusive do
      exclusive_booking { true }
      max_capacity { 50 }
      description { "Private event: #{Faker::Lorem.sentence}" }
    end
    
    trait :limited_capacity do
      max_capacity { 30 }
    end
    
    trait :past_event do
      event_date { Date.current - 10.days }
    end
    
    trait :upcoming_event do
      event_date { Date.current + 5.days }
    end
    
    trait :all_day do
      start_time { Time.parse('11:00:00') }
      end_time { Time.parse('23:00:00') }
    end
  end
end
