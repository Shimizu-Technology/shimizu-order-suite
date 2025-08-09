FactoryBot.define do
  factory :wholesale_fundraiser_counter, class: 'Wholesale::FundraiserCounter' do
    fundraiser { nil }
    counter { 1 }
    last_reset_date { "2025-08-08" }
  end
end
