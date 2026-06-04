require "rails_helper"
require "ostruct"

RSpec.describe "HL1 hardening fixes" do
  describe "tenant isolation and admin authorization" do
    it "authenticates orders before enforcing tenant access" do
      filters = OrdersController._process_action_callbacks
                                .select { |callback| callback.kind == :before }
                                .map(&:filter)

      expect(filters.index(:set_current_tenant)).to be < filters.index(:authorize_request)
      expect(filters.index(:authorize_request)).to be < filters.index(:ensure_tenant_context)

      application_source = Rails.root.join("app/controllers/application_controller.rb").read
      tenant_source = Rails.root.join("app/controllers/concerns/tenant_isolation.rb").read

      set_current_tenant_body = tenant_source[/def set_current_tenant.*?^  end/m]

      expect(application_source).to include("validate_tenant_access(@current_restaurant) unless performed?")
      expect(set_current_tenant_body).not_to include("validate_tenant_access(")
    end

    it "does not rely on production-only tenant monkey patches" do
      tenant_patch = Rails.root.join("config/initializers/tenant_isolation_patch.rb").read
      admin_patch = Rails.root.join("config/initializers/admin_controllers_patch.rb").read

      [ tenant_patch, admin_patch ].each do |source|
        expect(source).not_to include("class_eval")
        expect(source).not_to include("prepend")
        expect(source).not_to include("Rails.env.production?")
      end
    end

    it "protects admin system actions with auth, admin, and tenant checks" do
      filters = Admin::SystemController._process_action_callbacks
                                       .select { |callback| callback.kind == :before }
                                       .map(&:filter)

      expect(filters.index(:authorize_request)).to be < filters.index(:authorize_admin)
      expect(filters.index(:authorize_admin)).to be < filters.index(:ensure_tenant_context)
      expect(Admin::SystemController.new.send(:global_access_permitted?)).to eq(false)
    end

    it "requires admins for merchandise collection mutations" do
      source = Rails.root.join("app/controllers/merchandise_collections_controller.rb").read

      expect(source).to include("before_action :authorize_request, except: [ :index, :show ]")
      expect(source).to include("before_action :require_admin!, except: [ :index, :show ]")
    end
  end

  describe "order creation transaction", type: :request do
    let(:restaurant) do
      create(
        :restaurant,
        vip_enabled: true,
        admin_settings: {
          "payment_gateway" => {
            "test_mode" => true,
            "secret_key" => "sk_test_redacted"
          }
        }
      )
    end
    let!(:location) { create(:location, restaurant: restaurant, is_default: true) }
    let!(:menu) { create(:menu, restaurant: restaurant) }
    let!(:menu_item) { create(:menu_item, menu: menu, enable_stock_tracking: true, stock_quantity: 5) }
    let!(:vip_code) do
      VipAccessCode.create!(
        restaurant: restaurant,
        code: "VIP-ROLLBACK",
        name: "Rollback Test",
        max_uses: 1,
        current_uses: 0,
        is_active: true
      )
    end

    before do
      allow_any_instance_of(AnalyticsService).to receive(:track)
      allow_any_instance_of(OrdersController).to receive(:process_initial_order_inventory!).and_return(
        success: false,
        errors: [ "simulated inventory race" ],
        low_stock_variants: []
      )
    end

    it "rejects order lookup without a payment intent client secret" do
      post "/orders/by_transaction",
           params: { restaurant_id: restaurant.id, transaction_id: "pi_lookup_hl1" },
           headers: {
             "X-Frontend-ID" => "hafaloha",
             "X-Frontend-Restaurant-ID" => restaurant.id.to_s
           }

      expect(response).to have_http_status(:forbidden)
    end

    it "finds an existing order by Stripe transaction id for checkout recovery without exposing PII" do
      order = create(
        :order,
        restaurant: restaurant,
        location: location,
        transaction_id: "pi_lookup_hl1",
        payment_status: "completed"
      )

      allow(Stripe::PaymentIntent).to receive(:retrieve)
        .with("pi_lookup_hl1", { api_key: "sk_test_redacted" })
        .and_return(
          OpenStruct.new(
            id: "pi_lookup_hl1",
            client_secret: "pi_lookup_hl1_secret_redacted",
            metadata: { "restaurant_id" => restaurant.id.to_s }
          )
        )

      post "/orders/by_transaction",
           params: {
             restaurant_id: restaurant.id,
             transaction_id: "pi_lookup_hl1",
             payment_intent_client_secret: "pi_lookup_hl1_secret_redacted"
           },
           headers: {
             "X-Frontend-ID" => "hafaloha",
             "X-Frontend-Restaurant-ID" => restaurant.id.to_s
           }

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(order.id)
      expect(json).to include("items" => [], "merchandise_items" => [])
      expect(json).not_to include("contact_name", "contact_email", "contact_phone", "special_instructions")
    end

    it "rolls back order, payment, and VIP usage when final inventory processing fails" do
      expect do
        post "/orders",
             params: {
               restaurant_id: restaurant.id,
               order: {
                 items: [
                   {
                     id: menu_item.id,
                     name: menu_item.name,
                     price: menu_item.price,
                     quantity: 1
                   }
                 ],
                 total: 10.99,
                 contact_name: "Test Guest",
                 contact_email: "guest@example.com",
                 contact_phone: "+16711234567",
                 vip_code: "VIP-ROLLBACK",
                 payment_method: "credit_card",
                 location_id: location.id
               }
             },
             headers: {
               "X-Frontend-ID" => "hafaloha",
               "X-Frontend-Restaurant-ID" => restaurant.id.to_s
             }
      end.not_to change(Order, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Inventory processing failed")
      expect(vip_code.reload.current_uses).to eq(0)
      expect(OrderPayment.count).to eq(0)
    end

    it "rejects over-requested menu item stock before persisting the order" do
      expect do
        post "/orders",
             params: {
               restaurant_id: restaurant.id,
               order: {
                 items: [
                   {
                     id: menu_item.id,
                     name: menu_item.name,
                     price: menu_item.price,
                     quantity: menu_item.stock_quantity + 1
                   }
                 ],
                 total: 10.99,
                 contact_name: "Test Guest",
                 contact_email: "guest@example.com",
                 contact_phone: "+16711234567",
                 vip_code: "VIP-ROLLBACK",
                 payment_method: "credit_card",
                 location_id: location.id
               }
             },
             headers: {
               "X-Frontend-ID" => "hafaloha",
               "X-Frontend-Restaurant-ID" => restaurant.id.to_s
             }
      end.not_to change(Order, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Insufficient stock")
      expect(json["details"]).to include(
        "#{menu_item.name}: only #{menu_item.stock_quantity} available (requested #{menu_item.stock_quantity + 1})"
      )
    end

    it "rejects menu item IDs from another restaurant before persisting the order" do
      other_restaurant = create(:restaurant)
      other_menu = create(:menu, restaurant: other_restaurant)
      other_item = create(:menu_item, menu: other_menu)

      expect do
        post "/orders",
             params: {
               restaurant_id: restaurant.id,
               order: {
                 items: [
                   {
                     id: other_item.id,
                     name: other_item.name,
                     price: other_item.price,
                     quantity: 1
                   }
                 ],
                 total: 10.99,
                 contact_name: "Test Guest",
                 contact_email: "guest@example.com",
                 contact_phone: "+16711234567",
                 vip_code: "VIP-ROLLBACK",
                 payment_method: "credit_card",
                 location_id: location.id
               }
             },
             headers: {
               "X-Frontend-ID" => "hafaloha",
               "X-Frontend-Restaurant-ID" => restaurant.id.to_s
             }
      end.not_to change(Order, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to eq("Menu items not found: #{other_item.id}")
    end

    it "does not deduct later merchandise items when an earlier merchandise item fails" do
      collection = MerchandiseCollection.create!(restaurant: restaurant, name: "Shirts")
      merch_item = MerchandiseItem.create!(merchandise_collection: collection, name: "Logo Shirt", base_price: 20)
      variant = MerchandiseVariant.create!(
        merchandise_item: merch_item,
        size: "M",
        color: "Black",
        stock_quantity: 3,
        price_adjustment: 0
      )
      order = create(
        :order,
        restaurant: restaurant,
        location: location,
        merchandise_items: [
          { "merchandise_variant_id" => -1, "name" => "Missing shirt", "quantity" => 1 },
          { "merchandise_variant_id" => variant.id, "name" => "Logo Shirt", "quantity" => 1 }
        ]
      )
      result = { success: true, errors: [], low_stock_variants: [] }

      OrdersController.new.send(:process_initial_merchandise_inventory!, order, result)

      expect(result[:success]).to eq(false)
      expect(result[:errors]).to include("Missing shirt: variant not found")
      expect(variant.reload.stock_quantity).to eq(3)
    end

    it "rejects Stripe confirmation requests without a payment intent id" do
      post "/stripe/confirm_intent", params: { restaurant_id: restaurant.id }

      expect(response).to have_http_status(:bad_request)
      expect(json["error"]).to eq("payment_intent_id is required")
    end
  end

  describe TenantStripeService do
    let(:restaurant) do
      create(
        :restaurant,
        admin_settings: {
          "payment_gateway" => {
            "test_mode" => false,
            "secret_key" => "sk_test_redacted"
          }
        }
      )
    end

    it "creates card-only PaymentIntents tagged with the current restaurant" do
      fake_intent = OpenStruct.new(
        id: "pi_test_hl1",
        client_secret: "pi_test_hl1_secret_redacted",
        payment_method_types: [ "card" ]
      )

      expect(Stripe::PaymentIntent).to receive(:create) do |payload, options|
        expect(payload[:payment_method_types]).to eq([ "card" ])
        expect(payload[:metadata]).to include(
          restaurant_id: restaurant.id,
          checkout_mode: "card_only_v1"
        )
        expect(options[:api_key]).to eq("sk_test_redacted")
        fake_intent
      end

      result = described_class.new(restaurant).create_payment_intent("12.34")

      expect(result).to include(
        success: true,
        payment_intent_id: "pi_test_hl1",
        payment_method_types: [ "card" ]
      )
    end

    it "rejects retrieved PaymentIntents without restaurant metadata" do
      untagged_intent = OpenStruct.new(
        id: "pi_untagged",
        metadata: {}
      )

      allow(Stripe::PaymentIntent).to receive(:retrieve)
        .with("pi_untagged", { api_key: "sk_test_redacted" })
        .and_return(untagged_intent)

      result = described_class.new(restaurant).retrieve_payment_intent("pi_untagged")

      expect(result[:success]).to eq(false)
      expect(result[:status]).to eq(:forbidden)
      expect(result[:errors]).to include("Payment intent is missing restaurant metadata")
    end

    it "rejects retrieved PaymentIntents from another restaurant" do
      foreign_intent = OpenStruct.new(
        id: "pi_foreign",
        metadata: { "restaurant_id" => (restaurant.id + 1).to_s }
      )

      allow(Stripe::PaymentIntent).to receive(:retrieve)
        .with("pi_foreign", { api_key: "sk_test_redacted" })
        .and_return(foreign_intent)

      result = described_class.new(restaurant).retrieve_payment_intent("pi_foreign")

      expect(result[:success]).to eq(false)
      expect(result[:status]).to eq(:forbidden)
      expect(result[:errors]).to include("Payment intent does not belong to this restaurant")
    end
  end
end
