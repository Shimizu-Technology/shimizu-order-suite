FactoryBot.define do
  factory :order_acknowledgment do
    association :order, :with_user
    user { order.user }
    acknowledged_at { Time.current }
  end
end
