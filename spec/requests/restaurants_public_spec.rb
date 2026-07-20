require "rails_helper"

RSpec.describe "Public restaurant details", type: :request do
  let(:restaurant) do
    create(
      :restaurant,
      admin_settings: {
        "hero_image_url" => "https://cdn.example.com/hero.webp",
        "custom_pickup_hours" => "Monday-Friday, 8:30 AM-4:00 PM",
        "payment_gateway" => {
          "payment_processor" => "stripe",
          "publishable_key" => "pk_test_public",
          "secret_key" => "server-secret",
          "webhook_secret" => "webhook-secret"
        },
        "web_push" => {
          "vapid_public_key" => "public-vapid-key",
          "vapid_private_key" => "private-vapid-key"
        },
        "pushover" => {
          "user_key" => "private-user-key",
          "app_token" => "private-app-token"
        }
      }
    )
  end

  before do
    allow(TokenService).to receive(:token_revoked?).and_return(false)
  end

  it "returns only explicitly public settings to anonymous visitors" do
    get "/restaurants/#{restaurant.id}"

    expect(response).to have_http_status(:ok)
    settings = json.fetch("admin_settings")

    expect(settings).to include(
      "hero_image_url" => "https://cdn.example.com/hero.webp",
      "custom_pickup_hours" => "Monday-Friday, 8:30 AM-4:00 PM"
    )
    expect(settings.fetch("payment_gateway")).to eq(
      "payment_processor" => "stripe",
      "publishable_key" => "pk_test_public"
    )
    expect(settings).not_to have_key("web_push")
    expect(settings).not_to have_key("pushover")
  end

  it "preserves the existing full settings response for authenticated admins" do
    admin = create(:user, :admin, restaurant: restaurant)
    token = TokenService.generate_token(admin)

    get "/restaurants/#{restaurant.id}", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    settings = json.fetch("admin_settings")
    expect(settings.dig("payment_gateway", "secret_key")).to eq("server-secret")
    expect(settings.dig("web_push", "vapid_private_key")).to eq("private-vapid-key")
  end

  it "keeps an empty payment gateway object when only private keys are stored" do
    restaurant.update!(
      admin_settings: {
        "payment_gateway" => {
          "secret_key" => "server-secret",
          "webhook_secret" => "webhook-secret"
        }
      }
    )

    get "/restaurants/#{restaurant.id}"

    expect(response).to have_http_status(:ok)
    expect(json.fetch("admin_settings").fetch("payment_gateway")).to eq({})
  end
end
