require 'rails_helper'

RSpec.describe OrderAcknowledgment, type: :model do
  describe 'associations' do
    it 'belongs to an order' do
      expect(OrderAcknowledgment.reflect_on_association(:order).macro).to eq :belongs_to
    end

    it 'belongs to a user' do
      expect(OrderAcknowledgment.reflect_on_association(:user).macro).to eq :belongs_to
    end
  end

  describe 'validations' do
    it 'validates uniqueness of order_id scoped to user_id' do
      # Create a first acknowledgment
      acknowledgment = create(:order_acknowledgment)

      # Try to create a duplicate acknowledgment with the same order and user
      duplicate = build(:order_acknowledgment, order: acknowledgment.order, user: acknowledgment.user)

      # It should not be valid
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:order_id]).to include('has already been acknowledged by this user')
    end

    it 'allows different users to acknowledge the same order' do
      # Create a first acknowledgment
      acknowledgment = create(:order_acknowledgment)

      # Create a second acknowledgment with the same order but different user
      second_user = create(:user)
      second_acknowledgment = build(:order_acknowledgment, order: acknowledgment.order, user: second_user)

      # It should be valid
      expect(second_acknowledgment).to be_valid
    end

    it 'allows the same user to acknowledge different orders' do
      # Create a first acknowledgment
      acknowledgment = create(:order_acknowledgment)

      # Create a second acknowledgment with the same user but different order
      second_order = create(:order)
      second_acknowledgment = build(:order_acknowledgment, order: second_order, user: acknowledgment.user)

      # It should be valid
      expect(second_acknowledgment).to be_valid
    end
  end

  describe 'timestamps' do
    it 'sets acknowledged_at to the current time by default' do
      acknowledgment = create(:order_acknowledgment, acknowledged_at: nil)
      expect(acknowledgment.acknowledged_at).not_to be_nil
    end
  end
end
