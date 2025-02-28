FactoryBot.define do
  factory :option_group do
    name { Faker::Food.ingredient + " Options" }
    min_select { 0 }
    max_select { 1 }
    required { false }
    association :menu_item
    
    trait :required do
      required { true }
      min_select { 1 }
    end
    
    trait :multiple do
      max_select { 3 }
    end
    
    trait :with_options do
      after(:create) do |option_group|
        create_list(:option, 3, option_group: option_group)
      end
    end
  end
end
