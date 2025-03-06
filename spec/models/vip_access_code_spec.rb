require 'rails_helper'

RSpec.describe VipAccessCode, type: :model do
  describe 'associations' do
    it { should belong_to(:special_event) }
    it { should belong_to(:restaurant) }
    it { should belong_to(:user).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:code) }
    
    it 'validates uniqueness of code scoped to restaurant_id' do
      restaurant = create(:restaurant)
      special_event = create(:special_event, restaurant: restaurant)
      create(:vip_access_code, code: 'TEST-CODE', restaurant: restaurant, special_event: special_event)
      
      duplicate_code = build(:vip_access_code, code: 'TEST-CODE', restaurant: restaurant, special_event: special_event)
      expect(duplicate_code).not_to be_valid
      
      # Different restaurant should allow same code
      other_restaurant = create(:restaurant)
      other_event = create(:special_event, restaurant: other_restaurant)
      different_restaurant_code = build(:vip_access_code, code: 'TEST-CODE', restaurant: other_restaurant, special_event: other_event)
      expect(different_restaurant_code).to be_valid
    end
  end

  describe 'scopes' do
    let(:restaurant) { create(:restaurant) }
    let(:special_event) { create(:special_event, restaurant: restaurant) }
    
    it 'active scope returns only active codes' do
      active_code = create(:vip_access_code, is_active: true, restaurant: restaurant, special_event: special_event)
      inactive_code = create(:vip_access_code, is_active: false, restaurant: restaurant, special_event: special_event)
      
      expect(VipAccessCode.active).to include(active_code)
      expect(VipAccessCode.active).not_to include(inactive_code)
    end
    
    it 'available scope returns active codes that are not expired' do
      active_code = create(:vip_access_code, is_active: true, restaurant: restaurant, special_event: special_event)
      expired_code = create(:vip_access_code, :expired, is_active: true, restaurant: restaurant, special_event: special_event)
      inactive_code = create(:vip_access_code, is_active: false, restaurant: restaurant, special_event: special_event)
      
      expect(VipAccessCode.available).to include(active_code)
      expect(VipAccessCode.available).not_to include(expired_code)
      expect(VipAccessCode.available).not_to include(inactive_code)
    end
    
    it 'by_group scope returns codes with matching group_id' do
      group_id = SecureRandom.uuid
      group_code1 = create(:vip_access_code, group_id: group_id, restaurant: restaurant, special_event: special_event)
      group_code2 = create(:vip_access_code, group_id: group_id, restaurant: restaurant, special_event: special_event)
      other_code = create(:vip_access_code, group_id: SecureRandom.uuid, restaurant: restaurant, special_event: special_event)
      
      expect(VipAccessCode.by_group(group_id)).to include(group_code1, group_code2)
      expect(VipAccessCode.by_group(group_id)).not_to include(other_code)
    end
  end

  describe '#available?' do
    let(:restaurant) { create(:restaurant) }
    let(:special_event) { create(:special_event, restaurant: restaurant) }
    
    it 'returns true for active, non-expired codes with uses below max' do
      code = create(:vip_access_code, 
        is_active: true, 
        expires_at: 1.day.from_now, 
        max_uses: 5, 
        current_uses: 3,
        restaurant: restaurant,
        special_event: special_event
      )
      
      expect(code.available?).to be true
    end
    
    it 'returns false for inactive codes' do
      code = create(:vip_access_code, 
        is_active: false, 
        expires_at: 1.day.from_now, 
        max_uses: 5, 
        current_uses: 3,
        restaurant: restaurant,
        special_event: special_event
      )
      
      expect(code.available?).to be false
    end
    
    it 'returns false for expired codes' do
      code = create(:vip_access_code, 
        is_active: true, 
        expires_at: 1.day.ago, 
        max_uses: 5, 
        current_uses: 3,
        restaurant: restaurant,
        special_event: special_event
      )
      
      expect(code.available?).to be false
    end
    
    it 'returns false for codes that reached max uses' do
      code = create(:vip_access_code, 
        is_active: true, 
        expires_at: 1.day.from_now, 
        max_uses: 5, 
        current_uses: 5,
        restaurant: restaurant,
        special_event: special_event
      )
      
      expect(code.available?).to be false
    end
    
    it 'returns true for codes with nil max_uses regardless of current_uses' do
      code = create(:vip_access_code, 
        is_active: true, 
        expires_at: 1.day.from_now, 
        max_uses: nil, 
        current_uses: 100,
        restaurant: restaurant,
        special_event: special_event
      )
      
      expect(code.available?).to be true
    end
    
    it 'returns true for codes with nil expires_at' do
      code = create(:vip_access_code, 
        is_active: true, 
        expires_at: nil, 
        max_uses: 5, 
        current_uses: 3,
        restaurant: restaurant,
        special_event: special_event
      )
      
      expect(code.available?).to be true
    end
  end

  describe '#use!' do
    let(:restaurant) { create(:restaurant) }
    let(:special_event) { create(:special_event, restaurant: restaurant) }
    
    it 'increments current_uses' do
      code = create(:vip_access_code, current_uses: 3, restaurant: restaurant, special_event: special_event)
      
      expect { code.use! }.to change { code.current_uses }.from(3).to(4)
    end
  end
end
