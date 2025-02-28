FactoryBot.define do
  factory :site_setting do
    hero_image_url { "https://example.com/images/hero-#{Faker::Lorem.word}.jpg" }
    spinner_image_url { "https://example.com/images/spinner-#{Faker::Lorem.word}.jpg" }
    
    trait :with_restaurant do
      association :restaurant
    end
    
    trait :without_images do
      hero_image_url { nil }
      spinner_image_url { nil }
    end
    
    trait :with_hero_only do
      hero_image_url { "https://example.com/images/hero-#{Faker::Lorem.word}.jpg" }
      spinner_image_url { nil }
    end
    
    trait :with_spinner_only do
      hero_image_url { nil }
      spinner_image_url { "https://example.com/images/spinner-#{Faker::Lorem.word}.jpg" }
    end
  end
end
