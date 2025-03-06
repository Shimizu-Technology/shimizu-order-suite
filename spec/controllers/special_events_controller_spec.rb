require 'rails_helper'

RSpec.describe SpecialEventsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user, restaurant: restaurant) }
  
  before do
    allow(controller).to receive(:current_user).and_return(user)
  end
  
  describe 'GET #index' do
    let!(:special_events) { create_list(:special_event, 3, restaurant: restaurant) }
    
    it 'returns a list of special events for the restaurant' do
      get :index, params: { restaurant_id: restaurant.id }
      
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body).length).to eq(3)
    end
    
    it 'returns empty array for non-existent restaurant' do
      get :index, params: { restaurant_id: 999999 }
      
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq([])
    end
  end
  
  describe 'POST #set_as_current' do
    let(:special_event) { create(:special_event, restaurant: restaurant) }
    let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'sets the special event as current for the restaurant' do
        post :set_as_current, params: { id: special_event.id }
        
        expect(response).to have_http_status(:success)
        
        restaurant.reload
        expect(restaurant.current_event_id).to eq(special_event.id)
      end
      
      it 'returns the updated restaurant in the response' do
        post :set_as_current, params: { id: special_event.id }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['restaurant']).to be_present
        expect(JSON.parse(response.body)['restaurant']['current_event_id']).to eq(special_event.id)
      end
    end
    
    context 'as a regular user' do
      it 'returns forbidden' do
        post :set_as_current, params: { id: special_event.id }
        
        expect(response).to have_http_status(:forbidden)
        
        restaurant.reload
        expect(restaurant.current_event_id).to be_nil
      end
    end
    
    context 'with invalid parameters' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'returns not found for non-existent special event' do
        post :set_as_current, params: { id: 999999 }
        
        expect(response).to have_http_status(:not_found)
      end
      
      it 'returns unprocessable entity for special event from another restaurant' do
        other_restaurant = create(:restaurant)
        other_event = create(:special_event, restaurant: other_restaurant)
        
        post :set_as_current, params: { id: other_event.id }
        
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
