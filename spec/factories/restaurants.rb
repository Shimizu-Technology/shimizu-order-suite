FactoryBot.define do
  factory :restaurant do
    sequence(:name) { |n| "Test Restaurant #{n}" }
    time_zone { "Pacific/Guam" }
    default_reservation_length { 90 }
    admin_settings do
      {
        'payment_gateway' => {
          'test_mode' => true,
          'environment' => 'sandbox',
          'merchant_id' => 'test_merchant_id',
          'public_key' => 'test_public_key',
          'private_key' => 'test_private_key'
        }
      }
    end
    allowed_origins { ["http://localhost:3000"] }
  end
end
