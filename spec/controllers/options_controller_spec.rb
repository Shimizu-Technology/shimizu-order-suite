require 'rails_helper'

RSpec.describe OptionsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:menu) { create(:menu, restaurant: restaurant) }
  let(:menu_item) { create(:menu_item, menu: menu) }
  let(:option_group) { create(:option_group, menu_item: menu_item) }
  let(:option) { create(:option, option_group: option_group) }
  let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
  let(:regular_user) { create(:user, restaurant: restaurant, role: 'user') }
  let(:auth_token) { token_generator(admin_user.id) }
  let(:regular_auth_token) { token_generator(regular_user.id) }

  before do
    # Mock the restaurant scope
    allow(controller).to receive(:set_restaurant_scope)
    allow(controller).to receive(:public_endpoint?).and_return(true)
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
          name: 'New Option',
          additional_price: 2.50,
          available: true
        }
      end

      it 'creates a new option' do
        expect {
          post :create, params: { option_group_id: option_group.id, option: valid_attributes }
        }.to change(Option, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['name']).to eq('New Option')
      end

      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: '',
            additional_price: 2.50,
            available: true
          }
        end

        it 'returns an unprocessable entity status' do
          post :create, params: { option_group_id: option_group.id, option: invalid_attributes }

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
          option_group_id: option_group.id,
          option: { name: 'Test', additional_price: 1.0, available: true }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        post :create, params: {
          option_group_id: option_group.id,
          option: { name: 'Test', additional_price: 1.0, available: true }
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
          name: 'Updated Option',
          additional_price: 3.50,
          available: false
        }
      end

      it 'updates the requested option' do
        patch :update, params: { id: option.id, option: new_attributes }

        expect(response).to have_http_status(:ok)
        option.reload
        expect(option.name).to eq('Updated Option')
        expect(option.additional_price).to eq(3.50)
        expect(option.available).to be false
      end

      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: ''
          }
        end

        it 'returns an unprocessable entity status' do
          patch :update, params: { id: option.id, option: invalid_attributes }

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
          id: option.id,
          option: { name: 'Updated' }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        patch :update, params: {
          id: option.id,
          option: { name: 'Updated' }
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

      it 'destroys the requested option' do
        option # Create the option

        expect {
          delete :destroy, params: { id: option.id }
        }.to change(Option, :count).by(-1)

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
        delete :destroy, params: { id: option.id }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        delete :destroy, params: { id: option.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
