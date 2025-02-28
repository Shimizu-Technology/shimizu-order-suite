require 'rails_helper'

RSpec.describe ReservationsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user) }
  let(:token) { JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base) }
  
  describe 'GET #index' do
    let!(:reservations) { create_list(:reservation, 3, restaurant: restaurant) }
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
        request.headers['X-Restaurant-ID'] = restaurant.id.to_s
      end
      
      it 'returns a success response with all reservations for the restaurant' do
        get :index
        expect(response).to have_http_status(:ok)
        expect(json_response.size).to eq(3)
      end
      
      it 'filters by status when provided' do
        seated_reservation = create(:reservation, :seated, restaurant: restaurant)
        get :index, params: { status: 'seated' }
        expect(response).to have_http_status(:ok)
        expect(json_response.size).to eq(1)
        expect(json_response.first[:id]).to eq(seated_reservation.id)
      end
      
      it 'filters by date when provided' do
        tomorrow = Date.tomorrow
        future_reservation = create(:reservation, restaurant: restaurant, start_time: tomorrow.to_datetime)
        get :index, params: { date: tomorrow.to_s }
        expect(response).to have_http_status(:ok)
        expect(json_response.size).to eq(1)
        expect(json_response.first[:id]).to eq(future_reservation.id)
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
    let(:reservation) { create(:reservation, restaurant: restaurant) }
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'returns the reservation' do
        get :show, params: { id: reservation.id }
        expect(response).to have_http_status(:ok)
        expect(json_response[:id]).to eq(reservation.id)
      end
      
      context 'when reservation does not exist' do
        it 'returns not found' do
          get :show, params: { id: 999 }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        get :show, params: { id: reservation.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'POST #create' do
    let(:valid_attributes) do
      {
        reservation: {
          restaurant_id: restaurant.id,
          contact_name: 'John Doe',
          contact_email: 'john@example.com',
          contact_phone: '123-456-7890',
          party_size: 4,
          start_time: 1.day.from_now.to_s,
          end_time: (1.day.from_now + 2.hours).to_s,
          special_requests: 'Window seat please',
          status: 'booked',
          duration_minutes: 120
        }
      }
    end
    
    let(:invalid_attributes) do
      {
        reservation: {
          restaurant_id: restaurant.id,
          contact_name: '',
          contact_email: 'invalid-email',
          party_size: 0,
          start_time: ''
        }
      }
    end
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      context 'with valid params' do
        it 'creates a new Reservation' do
          expect {
            post :create, params: valid_attributes
          }.to change(Reservation, :count).by(1)
        end
        
        it 'returns a success response with the new reservation' do
          post :create, params: valid_attributes
          expect(response).to have_http_status(:created)
          expect(json_response[:contact_name]).to eq('John Doe')
          expect(json_response[:contact_email]).to eq('john@example.com')
          expect(json_response[:party_size]).to eq(4)
        end
      end
      
      context 'with invalid params' do
        it 'does not create a new Reservation' do
          expect {
            post :create, params: invalid_attributes
          }.not_to change(Reservation, :count)
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
    let(:reservation) { create(:reservation, restaurant: restaurant, contact_name: 'Original Name') }
    
    let(:update_attributes) do
      {
        reservation: {
          contact_name: 'Updated Name',
          party_size: 6,
          special_requests: 'Updated request'
        }
      }
    end
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'updates the reservation' do
        put :update, params: { id: reservation.id }.merge(update_attributes)
        reservation.reload
        expect(reservation.contact_name).to eq('Updated Name')
        expect(reservation.party_size).to eq(6)
        expect(reservation.special_requests).to eq('Updated request')
      end
      
      it 'returns the updated reservation' do
        put :update, params: { id: reservation.id }.merge(update_attributes)
        expect(response).to have_http_status(:ok)
        expect(json_response[:contact_name]).to eq('Updated Name')
        expect(json_response[:party_size]).to eq(6)
        expect(json_response[:special_requests]).to eq('Updated request')
      end
      
      context 'when reservation does not exist' do
        it 'returns not found' do
          put :update, params: { id: 999 }.merge(update_attributes)
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        put :update, params: { id: reservation.id }.merge(update_attributes)
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'DELETE #destroy' do
    let!(:reservation) { create(:reservation, restaurant: restaurant) }
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'destroys the reservation' do
        expect {
          delete :destroy, params: { id: reservation.id }
        }.to change(Reservation, :count).by(-1)
      end
      
      it 'returns no content' do
        delete :destroy, params: { id: reservation.id }
        expect(response).to have_http_status(:no_content)
      end
      
      context 'when reservation does not exist' do
        it 'returns not found' do
          delete :destroy, params: { id: 999 }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        delete :destroy, params: { id: reservation.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
