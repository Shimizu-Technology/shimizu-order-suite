FactoryBot.define do
  factory :feature_flag do
    sequence(:name) { |n| "feature_flag_#{n}" }
    description { "A test feature flag" }
    enabled { false }
    global { false }
    association :restaurant
    configuration { {} }
  end
end
