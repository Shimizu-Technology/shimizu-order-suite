FactoryBot.define do
  factory :option_stock_audit do
    option { nil }
    user { nil }
    order { nil }
    previous_quantity { 1 }
    new_quantity { 1 }
    reason { "MyString" }
  end
end
