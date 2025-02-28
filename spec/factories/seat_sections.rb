FactoryBot.define do
  factory :seat_section do
    name { Faker::Restaurant.name }
    section_type { ['dining', 'bar', 'patio', 'private'].sample }
    orientation { ['horizontal', 'vertical'].sample }
    offset_x { rand(0..50) }
    offset_y { rand(0..50) }
    capacity { rand(10..50) }
    floor_number { 1 }
    association :layout
    
    trait :with_seats do
      after(:create) do |section|
        create_list(:seat, 4, seat_section: section)
      end
    end
    
    trait :dining do
      section_type { 'dining' }
    end
    
    trait :bar do
      section_type { 'bar' }
    end
    
    trait :patio do
      section_type { 'patio' }
    end
  end
end
