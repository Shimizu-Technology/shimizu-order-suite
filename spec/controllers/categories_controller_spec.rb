require 'rails_helper'

RSpec.describe CategoriesController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:menu) { create(:menu, restaurant: restaurant) }
  let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
  let(:regular_user) { create(:user, restaurant: restaurant, role: 'customer') }
  let(:auth_token) { token_generator(admin_user.id) }
  let(:regular_auth_token) { token_generator(regular_user.id) }

  before do
    # Mock the tenant isolation and set the restaurant context
    allow(controller).to receive(:set_current_tenant) do
      controller.instance_variable_set(:@current_restaurant, restaurant)
    end
    allow(controller).to receive(:ensure_tenant_context)
    allow(controller).to receive(:optional_authorize)
  end

  describe 'GET #index' do
    before do
      create_list(:category, 3, menu: menu)
    end

    context 'when accessed by public (no authentication)' do
      it 'returns a list of categories' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end
    end

    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it 'returns a list of categories' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end
    end

    context 'when authenticated as regular user' do
      before do
        request.headers['Authorization'] = "Bearer #{regular_auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(regular_user)
      end

      it 'returns a list of categories' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end
    end
  end
end
