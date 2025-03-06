require 'rails_helper'

RSpec.describe Restaurant, type: :model do
  describe 'VIP-related methods' do
    let(:restaurant) { create(:restaurant) }
    let(:special_event) { create(:special_event, restaurant: restaurant, vip_only_checkout: true) }
    let(:vip_code) { create(:vip_access_code, restaurant: restaurant, special_event: special_event) }
    
    before do
      restaurant.update(current_event_id: special_event.id)
    end
    
    describe '#vip_only_checkout?' do
      context 'when vip_only_mode is true and current event has vip_only_checkout' do
        before do
          restaurant.update(vip_only_mode: true)
        end
        
        it 'returns true' do
          expect(restaurant.vip_only_checkout?).to be true
        end
      end
      
      context 'when vip_only_mode is false' do
        before do
          restaurant.update(vip_only_mode: false)
        end
        
        it 'returns false even if current event has vip_only_checkout' do
          expect(restaurant.vip_only_checkout?).to be false
        end
      end
      
      context 'when there is no current event' do
        before do
          restaurant.update(current_event_id: nil, vip_only_mode: true)
        end
        
        it 'returns false' do
          expect(restaurant.vip_only_checkout?).to be false
        end
      end
      
      context 'when current event does not have vip_only_checkout' do
        before do
          special_event.update(vip_only_checkout: false)
          restaurant.update(vip_only_mode: true)
        end
        
        it 'returns false' do
          expect(restaurant.vip_only_checkout?).to be false
        end
      end
    end
    
    describe '#validate_vip_code' do
      context 'when vip_only_checkout is true' do
        before do
          restaurant.update(vip_only_mode: true)
        end
        
        it 'returns true for a valid code' do
          expect(restaurant.validate_vip_code(vip_code.code)).to be true
        end
        
        it 'returns false for an invalid code' do
          expect(restaurant.validate_vip_code('INVALID-CODE')).to be false
        end
      end
      
      context 'when vip_only_checkout is false' do
        before do
          restaurant.update(vip_only_mode: false)
        end
        
        it 'returns true regardless of code' do
          expect(restaurant.validate_vip_code('ANYTHING')).to be true
        end
      end
    end
    
    describe '#use_vip_code!' do
      context 'when vip_only_checkout is true' do
        before do
          restaurant.update(vip_only_mode: true)
        end
        
        it 'increments the code usage for a valid code' do
          expect {
            restaurant.use_vip_code!(vip_code.code)
            vip_code.reload
          }.to change(vip_code, :current_uses).by(1)
        end
        
        it 'does nothing for an invalid code' do
          expect {
            restaurant.use_vip_code!('INVALID-CODE')
          }.not_to change(vip_code, :current_uses)
        end
      end
      
      context 'when vip_only_checkout is false' do
        before do
          restaurant.update(vip_only_mode: false)
        end
        
        it 'does nothing regardless of code' do
          expect {
            restaurant.use_vip_code!(vip_code.code)
            vip_code.reload
          }.not_to change(vip_code, :current_uses)
        end
      end
    end
  end
end
