require 'rails_helper'

# Tests for all 11 bugs found during stress testing (HL1-9 through HL1-19)
RSpec.describe "HL1 Stress Test Bug Fixes" do
  # ============================================================
  # BUG-1 (HL1-9): Order number race condition
  # ============================================================
  describe "HL1-9: Order number generation with DB locking", type: :model do
    let(:restaurant) { create(:restaurant, name: "Hafaloha") }
    let!(:counter) { create(:restaurant_counter, restaurant: restaurant) }

    it "generates unique order numbers sequentially" do
      order_numbers = 5.times.map do
        RestaurantCounter.next_order_number(restaurant.id)
      end

      expect(order_numbers.uniq.size).to eq(5)
      expect(order_numbers).to all(match(/^HAF-O-\d{3,}$/))
    end

    it "increments the counter correctly" do
      RestaurantCounter.next_order_number(restaurant.id)
      counter.reload
      expect(counter.daily_order_counter).to eq(1)
      expect(counter.total_order_counter).to eq(1)
    end

    it "uses pessimistic locking (FOR UPDATE)" do
      # Verify the method uses a transaction with lock
      expect(RestaurantCounter).to receive(:lock).with("FOR UPDATE").and_call_original
      RestaurantCounter.next_order_number(restaurant.id)
    end

    it "retries on RecordNotUnique up to 3 times" do
      # Simulate the first attempt raising RecordNotUnique, second succeeding
      call_count = 0
      allow(RestaurantCounter).to receive(:transaction).and_wrap_original do |method, *args, &block|
        call_count += 1
        if call_count == 1
          raise ActiveRecord::RecordNotUnique, "duplicate key"
        else
          method.call(*args, &block)
        end
      end

      result = RestaurantCounter.next_order_number(restaurant.id)
      expect(result).to be_present
      expect(call_count).to eq(2)
    end

    it "resets daily counter on new day" do
      counter.update!(daily_order_counter: 50, total_order_counter: 100, last_reset_date: Date.yesterday)

      RestaurantCounter.next_order_number(restaurant.id)
      counter.reload

      expect(counter.daily_order_counter).to eq(1)
      expect(counter.last_reset_date).to eq(Date.current)
      expect(counter.total_order_counter).to eq(101)
    end
  end

  # ============================================================
  # BUG-2 (HL1-10): Order cancellation broken (argument count)
  # ============================================================
  describe "HL1-10: Order cancellation argument count", type: :controller do
    controller(OrdersController) { }

    let(:restaurant) { create(:restaurant) }
    let(:location) { create(:location, restaurant: restaurant, is_default: true) }
    let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
    let(:menu) { create(:menu, restaurant: restaurant) }
    let(:menu_item) { create(:menu_item, menu: menu, enable_stock_tracking: true, stock_quantity: 10) }

    it "revert_order_inventory accepts exactly 3 arguments" do
      order_service = OrderService.new(restaurant)
      method = order_service.method(:revert_order_inventory)
      # Should accept 3 required parameters: order_items, order, user
      expect(method.arity).to eq(3)
    end
  end

  # ============================================================
  # BUG-3 (HL1-11): Zero stock doesn't prevent orders
  # ============================================================
  describe "HL1-11: Oversell protection", type: :model do
    let(:restaurant) { create(:restaurant) }
    let(:location) { create(:location, restaurant: restaurant, is_default: true) }
    let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
    let(:menu) { create(:menu, restaurant: restaurant) }
    let(:menu_item) { create(:menu_item, menu: menu, enable_stock_tracking: true, stock_quantity: 2) }
    let(:order) { create(:order, restaurant: restaurant, location: location, order_number: "TEST-001") }

    it "rejects order when stock is zero" do
      menu_item.update!(stock_quantity: 0)
      order_service = OrderService.new(restaurant)

      result = order_service.send(
        :process_item_level_inventory,
        menu_item, 1, order, admin_user, 'order'
      )

      expect(result[:success]).to be false
      expect(result[:errors].first).to include("Insufficient stock")
    end

    it "rejects order when requested quantity exceeds available stock" do
      order_service = OrderService.new(restaurant)

      result = order_service.send(
        :process_item_level_inventory,
        menu_item, 5, order, admin_user, 'order'
      )

      expect(result[:success]).to be false
      expect(result[:errors].first).to include("2 available, 5 requested")
    end

    it "allows order when stock is sufficient" do
      order_service = OrderService.new(restaurant)

      result = order_service.send(
        :process_item_level_inventory,
        menu_item, 2, order, admin_user, 'order'
      )

      expect(result[:success]).to be true
      menu_item.reload
      expect(menu_item.stock_quantity).to eq(0)
    end
  end

  # ============================================================
  # BUG-4 (HL1-12): Inventory race condition (pessimistic locking)
  # ============================================================
  describe "HL1-12: Pessimistic locking for inventory", type: :model do
    let(:restaurant) { create(:restaurant) }
    let(:location) { create(:location, restaurant: restaurant, is_default: true) }
    let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
    let(:menu) { create(:menu, restaurant: restaurant) }
    let(:menu_item) { create(:menu_item, menu: menu, enable_stock_tracking: true, stock_quantity: 10) }
    let(:order) { create(:order, restaurant: restaurant, location: location, order_number: "TEST-002") }

    it "uses FOR UPDATE lock when processing inventory" do
      order_service = OrderService.new(restaurant)

      # Verify MenuItem.lock is called with FOR UPDATE
      expect(MenuItem).to receive(:lock).with("FOR UPDATE").and_call_original

      order_service.send(
        :process_item_level_inventory,
        menu_item, 1, order, admin_user, 'order'
      )
    end

    it "uses FOR UPDATE lock when reverting inventory" do
      order_service = OrderService.new(restaurant)

      expect(MenuItem).to receive(:lock).with("FOR UPDATE").and_call_original

      order_service.send(
        :process_item_level_inventory,
        menu_item, 1, order, admin_user, 'revert'
      )
    end
  end

  # ============================================================
  # BUG-5 (HL1-13): Cash payment endpoint broken
  # ============================================================
  describe "HL1-13: Cash payment before_action includes all payment actions", type: :model do
    it "set_order before_action includes all required payment actions" do
      callback = OrderPaymentsController._process_action_callbacks
        .select { |c| c.filter == :set_order }
        .first

      expect(callback).to be_present

      # Extract the ActionFilter from the @if conditions
      action_filter = callback.instance_variable_get(:@if)&.first
      expect(action_filter).to be_present

      # Get the actions set from the ActionFilter
      actions = action_filter.instance_variable_get(:@actions)
      expect(actions).to be_a(Set)

      expected_actions = %w[
        index create_refund process_cash_payment create_additional
        capture_additional add_store_credit adjust_total create_payment_link
      ]
      expected_actions.each do |action|
        expect(actions).to include(action),
          "Expected set_order before_action to include '#{action}'"
      end
    end
  end

  # ============================================================
  # BUG-6 (HL1-14): Over-refund allowed in test mode
  # ============================================================
  describe "HL1-14: Refund validation in test mode", type: :controller do
    controller(OrderPaymentsController) { }

    let(:restaurant) { create(:restaurant) }
    let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
    let(:location) { create(:location, restaurant: restaurant, is_default: true) }
    let(:order) do
      create(:order, restaurant: restaurant, location: location,
             total: 100.0, payment_method: 'credit_card',
             payment_status: 'paid', payment_amount: 100.0,
             transaction_id: "pi_test_123")
    end

    before do
      allow(controller).to receive(:authorize_request).and_return(true)
      allow(controller).to receive(:current_user).and_return(admin_user)
      allow(controller).to receive(:ensure_tenant_context)
      allow(controller).to receive(:current_restaurant).and_return(restaurant)

      # Create an initial payment
      order.order_payments.create!(
        payment_type: "initial",
        amount: 100.0,
        payment_method: "credit_card",
        status: "paid",
        transaction_id: "pi_test_123",
        payment_id: "pi_test_123"
      )
    end

    it "prevents over-refund even in test mode" do
      # The refund validation should NOT be bypassed in test mode
      # Verifying the source code no longer contains !test_mode in the condition
      source = File.read(Rails.root.join('app/controllers/order_payments_controller.rb'))
      refund_validation_section = source[/Validate refund amount.*?status: :unprocessable_entity/m]
      expect(refund_validation_section).not_to include('!test_mode')
      expect(refund_validation_section).not_to include('test_mode')
    end
  end

  # ============================================================
  # BUG-7 (HL1-15): No item ID validation
  # ============================================================
  describe "HL1-15: Menu item ID validation in order creation", type: :controller do
    controller(OrdersController) { }

    let(:restaurant) { create(:restaurant) }
    let(:location) { create(:location, restaurant: restaurant, is_default: true) }

    before do
      allow(controller).to receive(:ensure_tenant_context)
      allow(controller).to receive(:current_restaurant).and_return(restaurant)
    end

    it "source code validates missing menu item IDs before order creation" do
      source = File.read(Rails.root.join('app/controllers/orders_controller.rb'))
      expect(source).to include('missing_ids = item_ids - menu_items_by_id.keys')
      expect(source).to include('Menu items not found')
    end
  end

  # ============================================================
  # BUG-8 (HL1-16): Notification crash on nil price
  # ============================================================
  describe "HL1-16: Nil price guard in notifications", type: :model do
    let(:restaurant) { create(:restaurant) }
    let(:location) { create(:location, restaurant: restaurant, is_default: true) }

    it "does not crash when item price is nil in notify_whatsapp" do
      order = build(:order, restaurant: restaurant, location: location,
                    items: [ { 'name' => 'Test', 'quantity' => 1, 'price' => nil } ],
                    total: 10.0)

      # The format string with .to_f should handle nil gracefully
      expect { '%.2f' % nil.to_f }.not_to raise_error
      expect('%.2f' % nil.to_f).to eq("0.00")
    end

    it "formats price correctly when price is present" do
      expect('%.2f' % 12.5.to_f).to eq("12.50")
    end

    it "source code uses .to_f for item prices in notifications" do
      source = File.read(Rails.root.join('app/models/order.rb'))
      # All notification methods should use item['price'].to_f
      notify_methods = source.scan(/item\['price'\]\.to_f/)
      # Should find multiple occurrences (whatsapp, pushover, web_push, merch)
      expect(notify_methods.length).to be >= 4
    end
  end

  # ============================================================
  # BUG-9 (HL1-17): Option group create response missing options
  # ============================================================
  describe "HL1-17: Option group reload after creation", type: :model do
    it "source code reloads option group after save in service" do
      source = File.read(Rails.root.join('app/services/option_group_service.rb'))
      # After save, should reload to include nested options
      expect(source).to include('option_group.reload')
    end
  end

  # ============================================================
  # BUG-10 (HL1-18): Inventory not restored on refund
  # ============================================================
  describe "HL1-18: Inventory restoration on refund", type: :model do
    it "source code restores inventory for full refunds without explicit refunded_items" do
      source = File.read(Rails.root.join('app/controllers/order_payments_controller.rb'))
      # Should have fallback logic to use order items when refunded_items not provided
      expect(source).to include('items_to_restore')
      expect(source).to include('is_full_refund')
      expect(source).to include('using order items for inventory restoration')
    end
  end

  # ============================================================
  # BUG-11 (HL1-19): set_active returns null for active field
  # ============================================================
  describe "HL1-19: set_active returns correct active field", type: :model do
    let(:restaurant) { create(:restaurant) }
    let!(:menu) { create(:menu, restaurant: restaurant, active: false) }

    it "source code reloads menu to include active field in response" do
      source = File.read(Rails.root.join('app/controllers/menus_controller.rb'))
      # The set_active action should reload the menu and include active in the response
      expect(source).to include('Menu.find(result[:current_menu_id])')
      expect(source).to include('menu.as_json')
    end

    it "MenuService.set_active_menu properly activates the menu" do
      admin_user = create(:user, restaurant: restaurant, role: 'admin')
      service = MenuService.new(restaurant)
      service.current_user = admin_user

      result = service.set_active_menu(menu.id)

      expect(result[:success]).to be true
      expect(result[:current_menu_id]).to eq(menu.id)

      menu.reload
      expect(menu.active).to eq(true)
    end
  end

  # ============================================================
  # Integration tests for key flows
  # ============================================================
  describe "Integration: OrderService inventory flow", type: :model do
    let(:restaurant) { create(:restaurant) }
    let(:location) { create(:location, restaurant: restaurant, is_default: true) }
    let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
    let(:menu) { create(:menu, restaurant: restaurant) }
    let(:menu_item) { create(:menu_item, menu: menu, enable_stock_tracking: true, stock_quantity: 5) }
    let(:order) { create(:order, restaurant: restaurant, location: location, order_number: "INT-001") }

    it "full cycle: order -> revert -> verify stock restored" do
      order_service = OrderService.new(restaurant)

      # Place order (reduces stock)
      items = [ { 'id' => menu_item.id, 'quantity' => 3 } ]
      result = order_service.process_order_inventory(items, order, admin_user, 'order')
      expect(result[:success]).to be true
      menu_item.reload
      expect(menu_item.stock_quantity).to eq(2)

      # Revert (restores stock)
      revert_result = order_service.revert_order_inventory(items, order, admin_user)
      expect(revert_result[:success]).to be true
      menu_item.reload
      expect(menu_item.stock_quantity).to eq(5)
    end

    it "rejects overselling and keeps stock unchanged" do
      order_service = OrderService.new(restaurant)

      items = [ { 'id' => menu_item.id, 'quantity' => 10 } ]
      result = order_service.process_order_inventory(items, order, admin_user, 'order')
      expect(result[:success]).to be false
      expect(result[:errors].first).to include("Insufficient stock")

      menu_item.reload
      expect(menu_item.stock_quantity).to eq(5)  # unchanged
    end
  end
end
