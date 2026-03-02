FactoryBot.define do
  factory :site_setting do
    association :restaurant
    hero_image_url { "https://example.com/hero.jpg" }
    spinner_image_url { "https://example.com/spinner.gif" }
  end
end
