require 'rails_helper'

RSpec.describe OptionGroupsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:menu) { create(:menu, restaurant: restaurant) }
  let(:menu_item) { create(:menu_item, menu: menu) }
  let(:option_group) { create(:option_group, menu_item: menu_item) }
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
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
        
        create_list(:option_group, 3, menu_item: menu_item)
      end
      
      it 'returns a list of option groups for the menu item' do
        get :index, params: { menu_item_id: menu_item.id }
        
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end
    end
    
    context 'when authenticated as regular user' do
      before do
        request.headers['Authorization'] = "Bearer #{regular_auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(regular_user)
        
        create_list(:option_group, 3, menu_item: menu_item)
      end
      
      it 'returns a list of option groups for the menu item' do
        get :index, params: { menu_item_id: menu_item.id }
        
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end
    end
    
    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        get :index, params: { menu_item_id: menu_item.id }
        
        expect(response).to have_http_status(:unauthorized)
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
          name: 'New Option Group',
          required: true,
          min_select: 1,
          max_select: 3
        }
      end
      
      it 'creates a new option group' do
        expect {
          post :create, params: { menu_item_id: menu_item.id, option_group: valid_attributes }
        }.to change(OptionGroup, :count).by(1)
        
        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['name']).to eq('New Option Group')
      end
      
      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: '',
            required: true,
            min_select: 1,
            max_select: 3
          }
        end
        
        it 'returns an unprocessable entity status' do
          post :create, params: { menu_item_id: menu_item.id, option_group: invalid_attributes }
          
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
          menu_item_id: menu_item.id, 
          option_group: { name: 'Test', required: true, min_select: 1, max_select: 3 } 
        }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
    
    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        post :create, params: { 
          menu_item_id: menu_item.id, 
          option_group: { name: 'Test', required: true, min_select: 1, max_select: 3 } 
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
          name: 'Updated Option Group',
          required: false,
          min_select: 0,
          max_select: 2
        }
      end
      
      it 'updates the requested option group' do
        patch :update, params: { id: option_group.id, option_group: new_attributes }
        
        expect(response).to have_http_status(:ok)
        option_group.reload
        expect(option_group.name).to eq('Updated Option Group')
        expect(option_group.required).to be false
        expect(option_group.min_select).to eq(0)
        expect(option_group.max_select).to eq(2)
      end
      
      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: ''
          }
        end
        
        it 'returns an unprocessable entity status' do
          patch :update, params: { id: option_group.id, option_group: invalid_attributes }
          
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
          id: option_group.id, 
          option_group: { name: 'Updated' } 
        }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
    
    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        patch :update, params: { 
          id: option_group.id, 
          option_group: { name: 'Updated' } 
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
      
      it 'destroys the requested option group' do
        option_group # Create the option group
        
        expect {
          delete :destroy, params: { id: option_group.id }
        }.to change(OptionGroup, :count).by(-1)
        
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
        delete :destroy, params: { id: option_group.id }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
    
    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        delete :destroy, params: { id: option_group.id }
        
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
