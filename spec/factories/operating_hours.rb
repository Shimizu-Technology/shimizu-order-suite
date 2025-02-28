FactoryBot.define do
  factory :operating_hour do
    association :restaurant
    day_of_week { rand(0..6) }
    open_time { Time.parse('09:00:00') }
    close_time { Time.parse('22:00:00') }
    closed { false }
    
    trait :closed_day do
      closed { true }
      open_time { nil }
      close_time { nil }
    end
    
    trait :morning_shift do
      open_time { Time.parse('07:00:00') }
      close_time { Time.parse('15:00:00') }
    end
    
    trait :evening_shift do
      open_time { Time.parse('16:00:00') }
      close_time { Time.parse('23:00:00') }
    end
    
    trait :late_night do
      open_time { Time.parse('18:00:00') }
      close_time { Time.parse('02:00:00') }
    end
    
    trait :monday do
      day_of_week { 1 }
    end
    
    trait :tuesday do
      day_of_week { 2 }
    end
    
    trait :wednesday do
      day_of_week { 3 }
    end
    
    trait :thursday do
      day_of_week { 4 }
    end
    
    trait :friday do
      day_of_week { 5 }
    end
    
    trait :saturday do
      day_of_week { 6 }
    end
    
    trait :sunday do
      day_of_week { 0 }
    end
  end
end
