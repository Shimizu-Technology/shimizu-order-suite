require 'rails_helper'

RSpec.describe SpecialEvent, type: :model do
  describe 'VIP-related methods' do
    let(:restaurant) { create(:restaurant) }
    let(:special_event) { create(:special_event, restaurant: restaurant, vip_only_checkout: true) }
    let(:vip_code) { create(:vip_access_code, restaurant: restaurant, special_event: special_event) }
    
    describe '#vip_only?' do
      it 'returns true when vip_only_checkout is true' do
        expect(special_event.vip_only?).to be true
      end
      
      it 'returns false when vip_only_checkout is false' do
        special_event.update(vip_only_checkout: false)
        expect(special_event.vip_only?).to be false
      end
    end
    
    describe '#valid_vip_code?' do
      context 'when vip_only_checkout is true' do
        it 'returns true for a valid code' do
          expect(special_event.valid_vip_code?(vip_code.code)).to be true
        end
        
        it 'returns false for an invalid code' do
          expect(special_event.valid_vip_code?('INVALID-CODE')).to be false
        end
        
        it 'returns false for an expired code' do
          expired_code = create(:vip_access_code, :expired, restaurant: restaurant, special_event: special_event)
          expect(special_event.valid_vip_code?(expired_code.code)).to be false
        end
        
        it 'returns false for an inactive code' do
          inactive_code = create(:vip_access_code, :inactive, restaurant: restaurant, special_event: special_event)
          expect(special_event.valid_vip_code?(inactive_code.code)).to be false
        end
        
        it 'returns false for a code that reached max uses' do
          used_code = create(:vip_access_code, :used, restaurant: restaurant, special_event: special_event)
          expect(special_event.valid_vip_code?(used_code.code)).to be false
        end
      end
      
      context 'when vip_only_checkout is false' do
        before do
          special_event.update(vip_only_checkout: false)
        end
        
        it 'returns true regardless of code' do
          expect(special_event.valid_vip_code?('ANYTHING')).to be true
        end
      end
    end
    
    describe '#use_vip_code!' do
      it 'increments the code usage for a valid code' do
        expect {
          special_event.use_vip_code!(vip_code.code)
          vip_code.reload
        }.to change(vip_code, :current_uses).by(1)
      end
      
      it 'does nothing for an invalid code' do
        expect {
          special_event.use_vip_code!('INVALID-CODE')
        }.not_to change(vip_code, :current_uses)
      end
      
      context 'when vip_only_checkout is false' do
        before do
          special_event.update(vip_only_checkout: false)
        end
        
        it 'does nothing regardless of code' do
          expect {
            special_event.use_vip_code!(vip_code.code)
            vip_code.reload
          }.not_to change(vip_code, :current_uses)
        end
      end
    end
  end
end
