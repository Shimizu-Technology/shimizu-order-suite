FactoryBot.define do
  factory :option_group do
    sequence(:name) { |n| "Option Group #{n}" }
    association :menu_item
    required { false }
    min_select { 0 }
    max_select { 1 }
  end
end
