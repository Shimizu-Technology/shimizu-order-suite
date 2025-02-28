FactoryBot.define do
  factory :waitlist_entry do
    association :restaurant
    contact_name { Faker::Name.name }
    party_size { rand(1..6) }
    check_in_time { Time.current }
    status { 'waiting' }
    
    trait :seated do
      status { 'seated' }
    end
    
    trait :canceled do
      status { 'canceled' }
    end
    
    trait :no_show do
      status { 'no_show' }
    end
    
    trait :with_allocations do
      after(:create) do |waitlist_entry|
        create_list(:seat_allocation, 2, waitlist_entry: waitlist_entry)
      end
    end
  end
end
