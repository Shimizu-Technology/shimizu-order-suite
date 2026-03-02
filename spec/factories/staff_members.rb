FactoryBot.define do
  factory :staff_member do
    sequence(:name) { |n| "Staff Member #{n}" }
    position { "server" }
    association :restaurant
    active { true }
    house_account_balance { 0.0 }
  end
end
