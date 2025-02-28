FactoryBot.define do
  factory :seat_allocation do
    association :seat
    reservation { nil }
    waitlist_entry { nil }
    start_time { Time.current }
    end_time { Time.current + 2.hours }
    released_at { nil }
    
    trait :for_reservation do
      association :reservation
    end
    
    trait :for_waitlist do
      association :waitlist_entry
    end
    
    trait :released do
      released_at { Time.current - 30.minutes }
    end
    
    trait :future do
      start_time { 1.day.from_now }
      end_time { 1.day.from_now + 2.hours }
    end
  end
end
