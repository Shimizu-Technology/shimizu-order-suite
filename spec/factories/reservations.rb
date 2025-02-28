FactoryBot.define do
  factory :reservation do
    association :restaurant
    start_time { Time.current + 1.day }
    end_time { Time.current + 1.day + 2.hours }
    party_size { rand(1..6) }
    contact_name { Faker::Name.name }
    contact_phone { Faker::PhoneNumber.cell_phone }
    contact_email { Faker::Internet.email }
    deposit_amount { nil }
    reservation_source { ['online', 'phone', 'walk-in'].sample }
    special_requests { Faker::Lorem.sentence }
    status { 'booked' }
    duration_minutes { 120 }
    seat_preferences { [] }
    
    trait :seated do
      status { 'seated' }
    end
    
    trait :finished do
      status { 'finished' }
    end
    
    trait :canceled do
      status { 'canceled' }
    end
    
    trait :no_show do
      status { 'no_show' }
    end
    
    trait :with_seat_preferences do
      seat_preferences { ['window', 'quiet'].sample(rand(1..2)) }
    end
    
    trait :with_allocations do
      after(:create) do |reservation|
        create_list(:seat_allocation, 2, reservation: reservation)
      end
    end
  end
end
