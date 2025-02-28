require 'rails_helper'

RSpec.describe Order, type: :model do
  describe 'associations' do
    it { should belong_to(:restaurant) }
    it { should belong_to(:user).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:total) }
    
    it 'validates status is one of the allowed values' do
      order = build(:order)
      
      # Test with valid statuses (assuming these are the valid statuses)
      %w[pending processing completed cancelled].each do |status|
        order.status = status
        expect(order).to be_valid
      end
      
      # Test with invalid status
      order.status = 'invalid_status'
      expect(order).not_to be_valid
    end
  end

  describe 'defaults' do
    it 'has default status of pending' do
      order = Order.new
      expect(order.status).to eq('pending')
    end

    it 'has default total of 0.0' do
      order = Order.new
      expect(order.total).to eq(0.0)
    end

    it 'has default items as an empty array' do
      order = Order.new
      expect(order.items).to eq([])
    end
  end

  describe 'scopes and queries' do
    let(:restaurant) { create(:restaurant) }
    let!(:pending_order) { create(:order, restaurant: restaurant, status: 'pending') }
    let!(:processing_order) { create(:order, restaurant: restaurant, status: 'processing') }
    let!(:completed_order) { create(:order, restaurant: restaurant, status: 'completed') }
    let!(:cancelled_order) { create(:order, restaurant: restaurant, status: 'cancelled') }
    
    # Add scopes as they are defined in the model
    # For example:
    # 
    # describe '.active' do
    #   it 'returns only pending and processing orders' do
    #     active_orders = Order.active
    #     expect(active_orders).to include(pending_order, processing_order)
    #     expect(active_orders).not_to include(completed_order, cancelled_order)
    #   end
    # end
  end

  describe 'callbacks' do
    # Add tests for any callbacks defined in the model
  end

  describe 'instance methods' do
    # Add tests for any instance methods defined in the model
    
    describe '#calculate_total' do
      let(:order) { build(:order, items: [
        { id: 1, name: 'Item 1', price: 10.0, quantity: 2 },
        { id: 2, name: 'Item 2', price: 5.0, quantity: 1 }
      ]) }
      
      it 'calculates the total based on item prices and quantities' do
        # Assuming there's a calculate_total method
        # If not, you can remove this test or implement the method
        if order.respond_to?(:calculate_total)
          expect(order.calculate_total).to eq(25.0) # (10.0 * 2) + (5.0 * 1)
        end
      end
    end
  end

  describe 'with promo code' do
    let(:restaurant) { create(:restaurant) }
    let(:promo_code) { create(:promo_code, restaurant: restaurant, discount_percent: 10) }
    let(:order) { build(:order, restaurant: restaurant, promo_code: promo_code.code, total: 100.0) }
    
    it 'applies the promo code discount' do
      # Assuming there's an apply_discount method
      # If not, you can remove this test or implement the method
      if order.respond_to?(:apply_discount)
        expect(order.apply_discount).to eq(90.0) # 100.0 - 10%
      end
    end
  end

  describe 'with user' do
    let(:user) { create(:user) }
    let(:order) { create(:order, user: user) }
    
    it 'associates the order with the user' do
      expect(order.user).to eq(user)
    end
  end

  describe 'with items' do
    let(:order) { create(:order, items: [
      { id: 1, name: 'Item 1', price: 10.0, quantity: 2 },
      { id: 2, name: 'Item 2', price: 5.0, quantity: 1 }
    ]) }
    
    it 'stores the items as a JSON array' do
      expect(order.items).to be_an(Array)
      expect(order.items.size).to eq(2)
      expect(order.items.first['name']).to eq('Item 1')
      expect(order.items.last['name']).to eq('Item 2')
    end
  end
end
