FactoryBot.define do
  factory :feature_flag do
    name { "MyString" }
    description { "MyText" }
    enabled { false }
    global { false }
    restaurant_id { 1 }
    configuration { "" }
  end
end
