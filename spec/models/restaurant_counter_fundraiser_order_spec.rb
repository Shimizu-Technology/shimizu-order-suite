require 'rails_helper'

RSpec.describe RestaurantCounter, type: :model do
  describe "fundraiser order number generation" do
    let(:restaurant) { create(:restaurant, prefix: "TST") }
    let(:fundraiser) { create(:fundraiser, restaurant: restaurant, order_code: "F1") }
    
    before do
      # Reset counter to a known state
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      counter.update!(
        daily_order_counter: 0,
        daily_counter_date: Date.today
      )
      
      # Delete any existing fundraiser counters
      FundraiserCounter.where(restaurant_id: restaurant.id).delete_all
    end
    
    it "generates a fundraiser-specific order number format" do
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      order_number = counter.generate_fundraiser_order_number(fundraiser.id)
      
      expect(order_number).to match(/TST-F1-001/)
    end
    
    it "increments counter for subsequent fundraiser orders" do
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      
      first_number = counter.generate_fundraiser_order_number(fundraiser.id)
      second_number = counter.generate_fundraiser_order_number(fundraiser.id)
      
      expect(first_number).to match(/TST-F1-001/)
      expect(second_number).to match(/TST-F1-002/)
    end
    
    it "maintains separate counters for different fundraisers" do
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      fundraiser2 = create(:fundraiser, restaurant: restaurant, order_code: "F2")
      
      first_f1_number = counter.generate_fundraiser_order_number(fundraiser.id)
      first_f2_number = counter.generate_fundraiser_order_number(fundraiser2.id)
      second_f1_number = counter.generate_fundraiser_order_number(fundraiser.id)
      
      expect(first_f1_number).to match(/TST-F1-001/)
      expect(first_f2_number).to match(/TST-F2-001/)
      expect(second_f1_number).to match(/TST-F1-002/)
    end
    
    it "keeps regular order numbering independent from fundraiser numbering" do
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      
      # Generate a regular order number first
      regular_number = counter.generate_order_number
      
      # Then generate a fundraiser order number
      fundraiser_number = counter.generate_fundraiser_order_number(fundraiser.id)
      
      # Then another regular order number
      second_regular_number = counter.generate_order_number
      
      # Regular orders should have their own sequence
      expect(regular_number).to match(/TST-O-001/)
      expect(second_regular_number).to match(/TST-O-002/)
      
      # Fundraiser order should start at 001 regardless of regular orders
      expect(fundraiser_number).to match(/TST-F1-001/)
    end
    
    it "continues the same fundraiser counter sequence even after system restarts" do
      # Simulate first order
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      first_number = counter.generate_fundraiser_order_number(fundraiser.id)
      
      # Create a new FundraiserCounter record directly to simulate what's in the database
      expect(FundraiserCounter.where(restaurant_id: restaurant.id, fundraiser_id: fundraiser.id).count).to eq(1)
      
      # Simulate system restart by getting a fresh counter instance
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      second_number = counter.generate_fundraiser_order_number(fundraiser.id)
      
      # Should continue from where it left off
      expect(first_number).to match(/TST-F1-001/)
      expect(second_number).to match(/TST-F1-002/)
    end
    
    it "falls back to regular order number if fundraiser not found" do
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      invalid_id = Fundraiser.maximum(:id).to_i + 1000 # A non-existent ID
      
      order_number = counter.generate_fundraiser_order_number(invalid_id)
      
      expect(order_number).to match(/TST-O-\d{3}/)
    end
    
    it "falls back to regular order number if fundraiser has no order_code" do
      fundraiser.update!(order_code: nil)
      counter = RestaurantCounter.for_restaurant(restaurant.id)
      
      order_number = counter.generate_fundraiser_order_number(fundraiser.id)
      
      expect(order_number).to match(/TST-O-\d{3}/)
    end
    
    it "integrates with the next_order_number method" do
      order_number = RestaurantCounter.next_order_number(restaurant.id, fundraiser_id: fundraiser.id)
      expect(order_number).to match(/TST-F1-\d{3}/)
    end
  end
end
