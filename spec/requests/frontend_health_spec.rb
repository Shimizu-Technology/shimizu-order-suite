require "rails_helper"

RSpec.describe "Frontend health", type: :request do
  describe "GET /health/frontend" do
    it "returns a minimal readiness response for an existing restaurant" do
      restaurant = create(:restaurant)

      get "/health/frontend", params: { restaurant_id: restaurant.id }

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        "status" => "available",
        "restaurant_id" => restaurant.id
      )
    end

    it "rejects a missing restaurant id" do
      get "/health/frontend"

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("errors")).to include("restaurant_id is required")
    end

    it "rejects an invalid restaurant id" do
      get "/health/frontend", params: { restaurant_id: "not-a-number" }

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("errors")).to include("restaurant_id must be a positive integer")
    end

    it "returns not found for an unknown restaurant" do
      get "/health/frontend", params: { restaurant_id: 999_999 }

      expect(response).to have_http_status(:not_found)
      expect(json.fetch("errors")).to include("Restaurant not found")
    end
  end
end
