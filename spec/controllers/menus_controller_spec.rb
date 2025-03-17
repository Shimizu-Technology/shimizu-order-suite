require 'rails_helper'

RSpec.describe MenusController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:menu) { create(:menu, restaurant: restaurant) }
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
    before do
      create_list(:menu, 3, restaurant: restaurant)
    end

    it 'returns a list of menus' do
      get :index

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
    end

    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it 'returns a list of menus' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end
    end
  end

  describe 'GET #show' do
    it 'returns the specified menu' do
      get :show, params: { id: menu.id }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(menu.id)
    end

    context 'when menu does not exist' do
      it 'raises a RecordNotFound error' do
        expect {
          get :show, params: { id: 999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
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
          name: 'New Menu',
          active: true,
          restaurant_id: restaurant.id
        }
      end

      it 'creates a new menu' do
        expect {
          post :create, params: { menu: valid_attributes }
        }.to change(Menu, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['name']).to eq('New Menu')
      end

      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: '',
            active: true,
            restaurant_id: restaurant.id
          }
        end

        it 'returns an unprocessable entity status' do
          post :create, params: { menu: invalid_attributes }

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
          menu: { name: 'Test', active: true, restaurant_id: restaurant.id }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        post :create, params: {
          menu: { name: 'Test', active: true, restaurant_id: restaurant.id }
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
          name: 'Updated Menu',
          active: false
        }
      end

      it 'updates the requested menu' do
        patch :update, params: { id: menu.id, menu: new_attributes }

        expect(response).to have_http_status(:ok)
        menu.reload
        expect(menu.name).to eq('Updated Menu')
        expect(menu.active).to be false
      end

      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: ''
          }
        end

        it 'returns an unprocessable entity status' do
          patch :update, params: { id: menu.id, menu: invalid_attributes }

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
          id: menu.id,
          menu: { name: 'Updated' }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        patch :update, params: {
          id: menu.id,
          menu: { name: 'Updated' }
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

      it 'destroys the requested menu' do
        menu # Create the menu

        expect {
          delete :destroy, params: { id: menu.id }
        }.to change(Menu, :count).by(-1)

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
        delete :destroy, params: { id: menu.id }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        delete :destroy, params: { id: menu.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
