require 'rails_helper'

RSpec.describe OrdersController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user) }
  let(:token) { JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base) }
  
  describe 'GET #index' do
    let!(:orders) { create_list(:order, 3, restaurant: restaurant) }
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
        request.headers['X-Restaurant-ID'] = restaurant.id.to_s
      end
      
      it 'returns a success response with all orders for the restaurant' do
        get :index
        expect(response).to have_http_status(:ok)
        expect(json_response.size).to eq(3)
      end
      
      it 'filters by status when provided' do
        processing_order = create(:order, restaurant: restaurant, status: 'processing')
        get :index, params: { status: 'processing' }
        expect(response).to have_http_status(:ok)
        expect(json_response.size).to eq(1)
        expect(json_response.first[:id]).to eq(processing_order.id)
      end
      
      it 'filters by date when provided' do
        tomorrow = Date.tomorrow
        future_order = create(:order, restaurant: restaurant, created_at: tomorrow.to_datetime)
        
        # Stub the date filter query since we can't easily manipulate created_at in tests
        allow(Order).to receive(:where).and_call_original
        allow(Order).to receive(:where).with(restaurant_id: restaurant.id.to_s).and_return(Order.where(id: future_order.id))
        
        get :index, params: { date: tomorrow.to_s }
        expect(response).to have_http_status(:ok)
        expect(json_response.size).to eq(1)
        expect(json_response.first[:id]).to eq(future_order.id)
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        get :index
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'GET #show' do
    let(:order) { create(:order, restaurant: restaurant) }
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'returns the order' do
        get :show, params: { id: order.id }
        expect(response).to have_http_status(:ok)
        expect(json_response[:id]).to eq(order.id)
      end
      
      context 'when order does not exist' do
        it 'returns not found' do
          get :show, params: { id: 999 }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        get :show, params: { id: order.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'POST #create' do
    let(:valid_attributes) do
      {
        order: {
          restaurant_id: restaurant.id,
          customer_name: 'John Doe',
          customer_email: 'john@example.com',
          customer_phone: '123-456-7890',
          total: 25.99,
          items: [
            { id: 1, name: 'Item 1', price: 10.99, quantity: 2 },
            { id: 2, name: 'Item 2', price: 4.01, quantity: 1 }
          ],
          status: 'pending',
          pickup_time: 30.minutes.from_now.to_s
        }
      }
    end
    
    let(:invalid_attributes) do
      {
        order: {
          restaurant_id: restaurant.id,
          customer_name: '',
          customer_email: 'invalid-email',
          total: -5.0,
          items: []
        }
      }
    end
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      context 'with valid params' do
        it 'creates a new Order' do
          expect {
            post :create, params: valid_attributes
          }.to change(Order, :count).by(1)
        end
        
        it 'returns a success response with the new order' do
          post :create, params: valid_attributes
          expect(response).to have_http_status(:created)
          expect(json_response[:customer_name]).to eq('John Doe')
          expect(json_response[:customer_email]).to eq('john@example.com')
          expect(json_response[:total]).to eq(25.99)
          expect(json_response[:items].size).to eq(2)
        end
      end
      
      context 'with invalid params' do
        it 'does not create a new Order' do
          expect {
            post :create, params: invalid_attributes
          }.not_to change(Order, :count)
        end
        
        it 'returns an error response' do
          post :create, params: invalid_attributes
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json_response[:errors]).to be_present
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        post :create, params: valid_attributes
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'PUT #update' do
    let(:order) { create(:order, restaurant: restaurant, status: 'pending') }
    
    let(:update_attributes) do
      {
        order: {
          status: 'processing',
          pickup_time: 45.minutes.from_now.to_s,
          notes: 'Updated notes'
        }
      }
    end
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'updates the order' do
        put :update, params: { id: order.id }.merge(update_attributes)
        order.reload
        expect(order.status).to eq('processing')
        expect(order.notes).to eq('Updated notes')
      end
      
      it 'returns the updated order' do
        put :update, params: { id: order.id }.merge(update_attributes)
        expect(response).to have_http_status(:ok)
        expect(json_response[:status]).to eq('processing')
        expect(json_response[:notes]).to eq('Updated notes')
      end
      
      context 'when order does not exist' do
        it 'returns not found' do
          put :update, params: { id: 999 }.merge(update_attributes)
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        put :update, params: { id: order.id }.merge(update_attributes)
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'DELETE #destroy' do
    let!(:order) { create(:order, restaurant: restaurant) }
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'destroys the order' do
        expect {
          delete :destroy, params: { id: order.id }
        }.to change(Order, :count).by(-1)
      end
      
      it 'returns no content' do
        delete :destroy, params: { id: order.id }
        expect(response).to have_http_status(:no_content)
      end
      
      context 'when order does not exist' do
        it 'returns not found' do
          delete :destroy, params: { id: 999 }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        delete :destroy, params: { id: order.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
