require 'rails_helper'

RSpec.describe OrdersController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:special_event) { create(:special_event, restaurant: restaurant, vip_only_checkout: true) }
  let(:vip_code) { create(:vip_access_code, restaurant: restaurant, special_event: special_event) }
  let(:user) { create(:user, restaurant: restaurant) }
  
  before do
    restaurant.update(current_event_id: special_event.id, vip_only_mode: true)
    allow(controller).to receive(:current_user).and_return(user)
  end
  
  describe 'POST #create' do
    let(:valid_order_params) do
      {
        restaurant_id: restaurant.id,
        customer_name: 'Test Customer',
        customer_phone: '1234567890',
        items: [
          {
            menu_item_id: create(:menu_item, restaurant: restaurant).id,
            quantity: 1,
            price: 10.0
          }
        ],
        total: 10.0,
        vip_code: vip_code.code
      }
    end
    
    context 'when VIP-only checkout is enabled' do
      it 'creates an order with a valid VIP code' do
        expect {
          post :create, params: { order: valid_order_params }
        }.to change(Order, :count).by(1)
        
        expect(response).to have_http_status(:created)
      end
      
      it 'rejects an order without a VIP code' do
        params_without_code = valid_order_params.except(:vip_code)
        
        expect {
          post :create, params: { order: params_without_code }
        }.not_to change(Order, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['vip_required']).to be true
      end
      
      it 'rejects an order with an invalid VIP code' do
        params_with_invalid_code = valid_order_params.merge(vip_code: 'INVALID-CODE')
        
        expect {
          post :create, params: { order: params_with_invalid_code }
        }.not_to change(Order, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['vip_required']).to be true
      end
      
      it 'increments the VIP code usage when order is created' do
        expect {
          post :create, params: { order: valid_order_params }
          vip_code.reload
        }.to change(vip_code, :current_uses).by(1)
      end
    end
    
    context 'when VIP-only checkout is disabled' do
      before do
        restaurant.update(vip_only_mode: false)
      end
      
      it 'creates an order without requiring a VIP code' do
        params_without_code = valid_order_params.except(:vip_code)
        
        expect {
          post :create, params: { order: params_without_code }
        }.to change(Order, :count).by(1)
        
        expect(response).to have_http_status(:created)
      end
      
      it 'does not increment VIP code usage even if code is provided' do
        expect {
          post :create, params: { order: valid_order_params }
          vip_code.reload
        }.not_to change(vip_code, :current_uses)
      end
    end
  end
end
