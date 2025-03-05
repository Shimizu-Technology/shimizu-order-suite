require 'rails_helper'

RSpec.describe PromoCodesController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:promo_code) { create(:promo_code) }
  let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
  let(:regular_user) { create(:user, restaurant: restaurant, role: 'user') }
  let(:auth_token) { token_generator(admin_user.id) }
  let(:regular_auth_token) { token_generator(regular_user.id) }
  
  before do
    # Mock the restaurant scope
    allow(controller).to receive(:set_restaurant_scope)
    allow(controller).to receive(:public_endpoint?).and_return(true)
  end

  describe 'GET #index' do
    let!(:valid_promo) { create(:promo_code, valid_until: 1.month.from_now) }
    let!(:expired_promo) { create(:promo_code, valid_until: 1.day.ago) }
    let!(:unlimited_promo) { create(:promo_code, valid_until: nil) }
    
    context 'when accessed by public (no authentication)' do
      it 'returns only valid promo codes' do
        get :index
        
        expect(response).to have_http_status(:ok)
        promo_codes = JSON.parse(response.body)
        expect(promo_codes.size).to eq(2)
        expect(promo_codes.map { |p| p['id'] }).to include(valid_promo.id, unlimited_promo.id)
        expect(promo_codes.map { |p| p['id'] }).not_to include(expired_promo.id)
      end
    end
    
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'returns all promo codes including expired ones' do
        get :index
        
        expect(response).to have_http_status(:ok)
        promo_codes = JSON.parse(response.body)
        expect(promo_codes.size).to eq(3)
        expect(promo_codes.map { |p| p['id'] }).to include(valid_promo.id, expired_promo.id, unlimited_promo.id)
      end
    end
    
    context 'when authenticated as regular user' do
      before do
        request.headers['Authorization'] = "Bearer #{regular_auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(regular_user)
      end
      
      it 'returns only valid promo codes' do
        get :index
        
        expect(response).to have_http_status(:ok)
        promo_codes = JSON.parse(response.body)
        expect(promo_codes.size).to eq(2)
        expect(promo_codes.map { |p| p['id'] }).to include(valid_promo.id, unlimited_promo.id)
        expect(promo_codes.map { |p| p['id'] }).not_to include(expired_promo.id)
      end
    end
  end
  
  describe 'GET #show' do
    it 'returns the specified promo code by ID' do
      get :show, params: { id: promo_code.id }
      
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(promo_code.id)
    end
    
    it 'returns the specified promo code by code' do
      get :show, params: { id: promo_code.code }
      
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(promo_code.id)
    end
    
    context 'when promo code does not exist' do
      it 'returns a not found error' do
        get :show, params: { id: 'NONEXISTENT' }
        
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)).to have_key('error')
      end
    end
  end
  
  describe 'POST #create' do
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      let(:valid_attributes) do
        {
          code: 'NEWPROMO',
          discount_percent: 15,
          valid_from: Date.current,
          valid_until: 1.month.from_now,
          max_uses: 100,
          current_uses: 0,
          restaurant_id: restaurant.id
        }
      end
      
      it 'creates a new promo code' do
        expect {
          post :create, params: { promo_code: valid_attributes }
        }.to change(PromoCode, :count).by(1)
        
        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['code']).to eq('NEWPROMO')
      end
      
      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            code: '',
            discount_percent: 15
          }
        end
        
        it 'returns an unprocessable entity status' do
          post :create, params: { promo_code: invalid_attributes }
          
          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)).to have_key('errors')
        end
      end
    end
    
    context 'when authenticated as regular user' do
      before do
        request.headers['Authorization'] = "Bearer #{regular_auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(regular_user)
      end
      
      it 'returns a forbidden status' do
        post :create, params: { 
          promo_code: { code: 'USERPROMO', discount_percent: 10 } 
        }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
    
    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        post :create, params: { 
          promo_code: { code: 'GUESTPROMO', discount_percent: 10 } 
        }
        
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'PATCH/PUT #update' do
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      let(:new_attributes) do
        {
          code: 'UPDATEDPROMO',
          discount_percent: 20,
          max_uses: 200
        }
      end
      
      it 'updates the requested promo code' do
        patch :update, params: { id: promo_code.id, promo_code: new_attributes }
        
        expect(response).to have_http_status(:ok)
        promo_code.reload
        expect(promo_code.code).to eq('UPDATEDPROMO')
        expect(promo_code.discount_percent).to eq(20)
        expect(promo_code.max_uses).to eq(200)
      end
      
      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            code: ''
          }
        end
        
        it 'returns an unprocessable entity status' do
          patch :update, params: { id: promo_code.id, promo_code: invalid_attributes }
          
          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)).to have_key('errors')
        end
      end
    end
    
    context 'when authenticated as regular user' do
      before do
        request.headers['Authorization'] = "Bearer #{regular_auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(regular_user)
      end
      
      it 'returns a forbidden status' do
        patch :update, params: { 
          id: promo_code.id, 
          promo_code: { code: 'USERUPDATED' } 
        }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
    
    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        patch :update, params: { 
          id: promo_code.id, 
          promo_code: { code: 'GUESTUPDATED' } 
        }
        
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'DELETE #destroy' do
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'destroys the requested promo code' do
        promo_code # Create the promo code
        
        expect {
          delete :destroy, params: { id: promo_code.id }
        }.to change(PromoCode, :count).by(-1)
        
        expect(response).to have_http_status(:no_content)
      end
    end
    
    context 'when authenticated as regular user' do
      before do
        request.headers['Authorization'] = "Bearer #{regular_auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(regular_user)
      end
      
      it 'returns a forbidden status' do
        delete :destroy, params: { id: promo_code.id }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
    
    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        delete :destroy, params: { id: promo_code.id }
        
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
