require 'rails_helper'

RSpec.describe VipAccessController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:special_event) { create(:special_event, restaurant: restaurant, vip_only_checkout: true) }
  let(:vip_code) { create(:vip_access_code, restaurant: restaurant, special_event: special_event) }
  
  describe 'POST #validate' do
    context 'with a valid code' do
      it 'returns success' do
        post :validate, params: { restaurant_id: restaurant.id, code: vip_code.code }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['valid']).to be true
      end
    end
    
    context 'with an invalid code' do
      it 'returns unauthorized' do
        post :validate, params: { restaurant_id: restaurant.id, code: 'INVALID-CODE' }
        
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['valid']).to be false
      end
    end
    
    context 'when VIP is not required' do
      let(:special_event) { create(:special_event, restaurant: restaurant, vip_only_checkout: false) }
      
      it 'returns success regardless of code' do
        post :validate, params: { restaurant_id: restaurant.id, code: 'ANYTHING' }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['valid']).to be true
      end
    end
    
    context 'with a missing code' do
      it 'returns bad request' do
        post :validate, params: { restaurant_id: restaurant.id }
        
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['valid']).to be false
      end
    end
  end
  
  describe 'POST #use_code' do
    context 'with a valid code' do
      it 'increments the code usage and returns success' do
        expect {
          post :use_code, params: { restaurant_id: restaurant.id, code: vip_code.code }
          vip_code.reload
        }.to change(vip_code, :current_uses).by(1)
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['success']).to be true
      end
    end
    
    context 'with an invalid code' do
      it 'returns unauthorized' do
        post :use_code, params: { restaurant_id: restaurant.id, code: 'INVALID-CODE' }
        
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)['success']).to be false
      end
    end
    
    context 'when VIP is not required' do
      let(:special_event) { create(:special_event, restaurant: restaurant, vip_only_checkout: false) }
      
      it 'returns success without incrementing any code' do
        post :use_code, params: { restaurant_id: restaurant.id, code: 'ANYTHING' }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['success']).to be true
      end
    end
    
    context 'with a missing code' do
      it 'returns bad request' do
        post :use_code, params: { restaurant_id: restaurant.id }
        
        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)['success']).to be false
      end
    end
  end
end
