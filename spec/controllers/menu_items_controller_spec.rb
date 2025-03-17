require 'rails_helper'

RSpec.describe MenuItemsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:menu) { create(:menu, restaurant: restaurant) }
  let(:menu_item) { create(:menu_item, menu: menu) }
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
    context 'when accessed by public' do
      before do
        # Create some menu items
        create_list(:menu_item, 3, menu: menu, available: true)
        create(:menu_item, menu: menu, available: false)
        create(:menu_item, menu: menu, seasonal: true, available_from: Date.current + 1.month, available_until: Date.current + 2.months)
      end

      it 'returns only available and in-season menu items' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end

      context 'with category filter' do
        let(:category) { create(:category, restaurant: restaurant) }

        before do
          menu_item_with_category = create(:menu_item, menu: menu)
          create(:menu_item_category, menu_item: menu_item_with_category, category: category)
        end

        it 'returns only menu items in the specified category' do
          get :index, params: { category_id: category.id }

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body).size).to eq(1)
        end
      end
    end

    context 'when accessed by admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)

        # Create some menu items
        create_list(:menu_item, 3, menu: menu, available: true)
        create(:menu_item, menu: menu, available: false)
        create(:menu_item, menu: menu, seasonal: true, available_from: Date.current + 1.month, available_until: Date.current + 2.months)
      end

      it 'returns all menu items when show_all is true' do
        get :index, params: { show_all: true }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(5)
      end

      it 'returns only available and in-season menu items when show_all is not provided' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).size).to eq(3)
      end
    end
  end

  describe 'GET #show' do
    it 'returns the specified menu item' do
      get :show, params: { id: menu_item.id }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['id']).to eq(menu_item.id)
    end

    context 'when menu item does not exist' do
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
          name: 'New Menu Item',
          description: 'A delicious new menu item',
          price: 12.99,
          available: true,
          menu_id: menu.id
        }
      end

      it 'creates a new menu item' do
        expect {
          post :create, params: { menu_item: valid_attributes }
        }.to change(MenuItem, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['name']).to eq('New Menu Item')
      end

      context 'with category_ids' do
        let(:category) { create(:category, restaurant: restaurant) }

        it 'assigns the menu item to the specified categories' do
          post :create, params: {
            menu_item: valid_attributes.merge(category_ids: [ category.id ])
          }

          expect(response).to have_http_status(:created)
          menu_item = MenuItem.last
          expect(menu_item.categories).to include(category)
        end
      end

      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: '',
            price: -5,
            menu_id: menu.id
          }
        end

        it 'returns an unprocessable entity status' do
          post :create, params: { menu_item: invalid_attributes }

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
          menu_item: { name: 'Test', price: 10, menu_id: menu.id }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        post :create, params: {
          menu_item: { name: 'Test', price: 10, menu_id: menu.id }
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
          name: 'Updated Menu Item',
          price: 15.99,
          available: false
        }
      end

      it 'updates the requested menu item' do
        patch :update, params: { id: menu_item.id, menu_item: new_attributes }

        expect(response).to have_http_status(:ok)
        menu_item.reload
        expect(menu_item.name).to eq('Updated Menu Item')
        expect(menu_item.price).to eq(15.99)
        expect(menu_item.available).to be false
      end

      context 'with category_ids' do
        let(:category) { create(:category, restaurant: restaurant) }

        it 'updates the menu item categories' do
          patch :update, params: {
            id: menu_item.id,
            menu_item: { category_ids: [ category.id ] }
          }

          expect(response).to have_http_status(:ok)
          menu_item.reload
          expect(menu_item.categories).to include(category)
        end
      end

      context 'with invalid attributes' do
        let(:invalid_attributes) do
          {
            name: '',
            price: -5
          }
        end

        it 'returns an unprocessable entity status' do
          patch :update, params: { id: menu_item.id, menu_item: invalid_attributes }

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
          id: menu_item.id,
          menu_item: { name: 'Updated' }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        patch :update, params: {
          id: menu_item.id,
          menu_item: { name: 'Updated' }
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

      it 'destroys the requested menu item' do
        menu_item # Create the menu item

        expect {
          delete :destroy, params: { id: menu_item.id }
        }.to change(MenuItem, :count).by(-1)

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
        delete :destroy, params: { id: menu_item.id }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        delete :destroy, params: { id: menu_item.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST #upload_image' do
    context 'when authenticated as admin' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(admin_user)
        allow(S3Uploader).to receive(:upload).and_return('https://example.com/image.jpg')
      end

      let(:image_file) do
        # Mock a file upload instead of using a real file
        Rack::Test::UploadedFile.new(StringIO.new('test image content'), 'image/jpeg', original_filename: 'test_image.jpg')
      end

      it 'uploads the image and updates the menu item' do
        post :upload_image, params: { id: menu_item.id, image: image_file }

        expect(response).to have_http_status(:ok)
        expect(S3Uploader).to have_received(:upload)
        menu_item.reload
        expect(menu_item.image_url).to eq('https://example.com/image.jpg')
      end

      context 'when no image is provided' do
        it 'returns an unprocessable entity status' do
          post :upload_image, params: { id: menu_item.id }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)).to have_key('error')
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
        post :upload_image, params: { id: menu_item.id, image: 'test' }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when not authenticated' do
      it 'returns an unauthorized status' do
        post :upload_image, params: { id: menu_item.id, image: 'test' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
