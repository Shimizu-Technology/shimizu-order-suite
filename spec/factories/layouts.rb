FactoryBot.define do
  factory :layout do
    name { "#{Faker::Address.community} Layout" }
    association :restaurant
    sections_data { { sections: [] } }
    
    trait :with_sections do
      sections_data do
        {
          sections: [
            {
              id: 1,
              name: "Main Dining",
              type: "dining",
              x: 10,
              y: 10,
              width: 200,
              height: 200
            },
            {
              id: 2,
              name: "Bar Area",
              type: "bar",
              x: 220,
              y: 10,
              width: 150,
              height: 100
            }
          ]
        }
      end
      
      after(:create) do |layout|
        create(:seat_section, name: "Main Dining", layout: layout)
        create(:seat_section, name: "Bar Area", layout: layout)
      end
    end
  end
end
