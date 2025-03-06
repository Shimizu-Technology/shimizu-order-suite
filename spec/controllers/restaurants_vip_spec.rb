require 'rails_helper'

RSpec.describe RestaurantsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
  let(:regular_user) { create(:user, restaurant: restaurant, role: 'user') }
  
  describe 'PATCH #toggle_vip_mode' do
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'enables VIP-only mode' do
        patch :toggle_vip_mode, params: { id: restaurant.id, vip_only_mode: true }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['success']).to be true
        expect(JSON.parse(response.body)['vip_only_mode']).to be true
        
        restaurant.reload
        expect(restaurant.vip_only_mode).to be true
      end
      
      it 'disables VIP-only mode' do
        restaurant.update(vip_only_mode: true)
        
        patch :toggle_vip_mode, params: { id: restaurant.id, vip_only_mode: false }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['success']).to be true
        expect(JSON.parse(response.body)['vip_only_mode']).to be false
        
        restaurant.reload
        expect(restaurant.vip_only_mode).to be false
      end
      
      it 'returns the updated restaurant in the response' do
        patch :toggle_vip_mode, params: { id: restaurant.id, vip_only_mode: true }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['restaurant']).to be_present
        expect(JSON.parse(response.body)['restaurant']['id']).to eq(restaurant.id)
      end
    end
    
    context 'as a regular user' do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end
      
      it 'returns forbidden' do
        patch :toggle_vip_mode, params: { id: restaurant.id, vip_only_mode: true }
        
        expect(response).to have_http_status(:forbidden)
        
        restaurant.reload
        expect(restaurant.vip_only_mode).to be false
      end
    end
    
    context 'with invalid parameters' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'returns unprocessable entity for invalid restaurant' do
        patch :toggle_vip_mode, params: { id: 999999, vip_only_mode: true }
        
        expect(response).to have_http_status(:not_found)
      end
    end
  end
  
  describe 'PATCH #update' do
    let(:valid_update_params) do
      {
        name: 'Updated Restaurant Name',
        code_prefix: 'VIP'
      }
    end
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'updates the code_prefix' do
        patch :update, params: { id: restaurant.id, restaurant: valid_update_params }
        
        expect(response).to have_http_status(:success)
        
        restaurant.reload
        expect(restaurant.code_prefix).to eq('VIP')
      end
    end
  end
end
