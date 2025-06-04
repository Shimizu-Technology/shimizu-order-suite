FactoryBot.define do
  factory :fundraiser_counter do
    association :restaurant
    association :fundraiser
    counter_value { 0 }
  end
end
