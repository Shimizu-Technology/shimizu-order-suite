require 'rails_helper'

RSpec.describe RestaurantsController, type: :controller do
  describe 'GET #index' do
    let!(:restaurants) { create_list(:restaurant, 3) }
    
    it 'returns a success response with all restaurants' do
      get :index
      expect(response).to have_http_status(:ok)
      expect(json_response.size).to eq(3)
    end
  end
  
  describe 'GET #show' do
    let(:restaurant) { create(:restaurant) }
    
    it 'returns a success response with the requested restaurant' do
      get :show, params: { id: restaurant.id }
      expect(response).to have_http_status(:ok)
      expect(json_response[:id]).to eq(restaurant.id)
      expect(json_response[:name]).to eq(restaurant.name)
    end
    
    context 'when restaurant does not exist' do
      it 'returns a not found response' do
        get :show, params: { id: 999 }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
  
  describe 'POST #create' do
    let(:admin_user) { create(:user, role: 'admin') }
    let(:token) { JWT.encode({ user_id: admin_user.id }, Rails.application.credentials.secret_key_base) }
    
    let(:valid_attributes) do
      {
        name: 'New Restaurant',
        address: '123 Main St',
        phone: '555-123-4567',
        time_zone: 'Pacific/Guam',
        default_reservation_length: 90
      }
    end
    
    let(:invalid_attributes) do
      {
        name: '',
        address: '',
        time_zone: ''
      }
    end
    
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      context 'with valid params' do
        it 'creates a new Restaurant' do
          expect {
            post :create, params: { restaurant: valid_attributes }
          }.to change(Restaurant, :count).by(1)
        end
        
        it 'returns a success response with the new restaurant' do
          post :create, params: { restaurant: valid_attributes }
          expect(response).to have_http_status(:created)
          expect(json_response[:name]).to eq('New Restaurant')
          expect(json_response[:address]).to eq('123 Main St')
          expect(json_response[:phone]).to eq('555-123-4567')
          expect(json_response[:time_zone]).to eq('Pacific/Guam')
          expect(json_response[:default_reservation_length]).to eq(90)
        end
      end
      
      context 'with invalid params' do
        it 'does not create a new Restaurant' do
          expect {
            post :create, params: { restaurant: invalid_attributes }
          }.not_to change(Restaurant, :count)
        end
        
        it 'returns an error response' do
          post :create, params: { restaurant: invalid_attributes }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_response[:errors]).to be_present
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        post :create, params: { restaurant: valid_attributes }
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'when authenticated as non-admin' do
      let(:regular_user) { create(:user, role: 'customer') }
      let(:token) { JWT.encode({ user_id: regular_user.id }, Rails.application.credentials.secret_key_base) }
      
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'returns forbidden' do
        post :create, params: { restaurant: valid_attributes }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
  
  describe 'PUT #update' do
    let(:restaurant) { create(:restaurant, name: 'Original Name') }
    let(:admin_user) { create(:user, role: 'admin') }
    let(:token) { JWT.encode({ user_id: admin_user.id }, Rails.application.credentials.secret_key_base) }
    
    let(:update_attributes) do
      {
        name: 'Updated Name',
        address: 'Updated Address',
        phone: '555-987-6543'
      }
    end
    
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'updates the restaurant' do
        put :update, params: { id: restaurant.id, restaurant: update_attributes }
        restaurant.reload
        expect(restaurant.name).to eq('Updated Name')
        expect(restaurant.address).to eq('Updated Address')
        expect(restaurant.phone).to eq('555-987-6543')
      end
      
      it 'returns the updated restaurant' do
        put :update, params: { id: restaurant.id, restaurant: update_attributes }
        expect(response).to have_http_status(:ok)
        expect(json_response[:name]).to eq('Updated Name')
        expect(json_response[:address]).to eq('Updated Address')
        expect(json_response[:phone]).to eq('555-987-6543')
      end
      
      context 'when restaurant does not exist' do
        it 'returns a not found response' do
          put :update, params: { id: 999, restaurant: update_attributes }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        put :update, params: { id: restaurant.id, restaurant: update_attributes }
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'when authenticated as non-admin' do
      let(:regular_user) { create(:user, role: 'customer') }
      let(:token) { JWT.encode({ user_id: regular_user.id }, Rails.application.credentials.secret_key_base) }
      
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'returns forbidden' do
        put :update, params: { id: restaurant.id, restaurant: update_attributes }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
  
  describe 'DELETE #destroy' do
    let!(:restaurant) { create(:restaurant) }
    let(:admin_user) { create(:user, role: 'admin') }
    let(:token) { JWT.encode({ user_id: admin_user.id }, Rails.application.credentials.secret_key_base) }
    
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'destroys the restaurant' do
        expect {
          delete :destroy, params: { id: restaurant.id }
        }.to change(Restaurant, :count).by(-1)
      end
      
      it 'returns no content' do
        delete :destroy, params: { id: restaurant.id }
        expect(response).to have_http_status(:no_content)
      end
      
      context 'when restaurant does not exist' do
        it 'returns a not found response' do
          delete :destroy, params: { id: 999 }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        delete :destroy, params: { id: restaurant.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'when authenticated as non-admin' do
      let(:regular_user) { create(:user, role: 'customer') }
      let(:token) { JWT.encode({ user_id: regular_user.id }, Rails.application.credentials.secret_key_base) }
      
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'returns forbidden' do
        delete :destroy, params: { id: restaurant.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
