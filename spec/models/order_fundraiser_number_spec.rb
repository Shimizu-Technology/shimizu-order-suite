require 'rails_helper'

RSpec.describe Order, type: :model do
  describe "fundraiser order number assignment" do
    let(:restaurant) { create(:restaurant, prefix: "TST") }
    let(:fundraiser) { create(:fundraiser, restaurant: restaurant, order_code: "F1") }
    
    before do
      # Reset counter to a known state
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      counter.update!(
        daily_order_counter: 0,
        daily_counter_date: Date.today
      )
    end
    
    it "assigns a regular order number for non-fundraiser orders" do
      order = build(:order, restaurant: restaurant)
      order.valid? # Trigger callbacks
      expect(order.order_number).to match(/TST-O-\d{3}/)
    end
    
    it "assigns a fundraiser-specific order number for fundraiser orders" do
      order = build(:order, restaurant: restaurant, fundraiser: fundraiser, is_fundraiser_order: true)
      order.valid? # Trigger callbacks
      expect(order.order_number).to match(/TST-F1-\d{3}/)
    end
    
    it "respects the order of order number generation" do
      # Create several orders in a specific order
      orders = []
      
      # First regular order
      order1 = create(:order, restaurant: restaurant)
      orders << order1
      
      # First fundraiser order
      order2 = create(:order, restaurant: restaurant, fundraiser: fundraiser, is_fundraiser_order: true)
      orders << order2
      
      # Second regular order
      order3 = create(:order, restaurant: restaurant)
      orders << order3
      
      # Second fundraiser order
      order4 = create(:order, restaurant: restaurant, fundraiser: fundraiser, is_fundraiser_order: true)
      orders << order4
      
      # Verify the counters increment properly
      expect(orders[0].order_number).to match(/TST-O-001$/)
      expect(orders[1].order_number).to match(/TST-F1-001$/)
      expect(orders[2].order_number).to match(/TST-O-002$/)
      expect(orders[3].order_number).to match(/TST-F1-002$/)
    end
    
    it "falls back to regular order number if fundraiser has no order_code" do
      fundraiser_without_code = create(:fundraiser, restaurant: restaurant, order_code: nil)
      fundraiser_without_code.update_column(:order_code, nil) # Force nil to bypass validation
      
      order = build(:order, restaurant: restaurant, fundraiser: fundraiser_without_code, is_fundraiser_order: true)
      order.valid? # Trigger callbacks
      expect(order.order_number).to match(/TST-O-\d{3}/)
    end
  end
end
