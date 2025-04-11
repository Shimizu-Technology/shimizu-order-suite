FactoryBot.define do
  factory :audit_log do
    restaurant_id { 1 }
    user_id { 1 }
    action { "MyString" }
    resource_type { "MyString" }
    resource_id { 1 }
    details { "" }
    ip_address { "MyString" }
  end
end
