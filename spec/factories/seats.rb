FactoryBot.define do
  factory :seat do
    label { "#{('A'..'Z').to_a.sample}#{rand(1..20)}" }
    position_x { rand(0..300) }
    position_y { rand(0..300) }
    capacity { rand(1..6) }
    association :seat_section
    
    trait :single do
      capacity { 1 }
    end
    
    trait :double do
      capacity { 2 }
    end
    
    trait :large do
      capacity { 4 }
    end
    
    trait :with_allocation do
      after(:create) do |seat|
        create(:seat_allocation, seat: seat)
      end
    end
  end
end
