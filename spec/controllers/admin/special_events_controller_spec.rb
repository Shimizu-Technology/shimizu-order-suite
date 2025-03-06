require 'rails_helper'

RSpec.describe Admin::SpecialEventsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
  let(:regular_user) { create(:user, restaurant: restaurant, role: 'user') }
  
  describe 'GET #index' do
    let!(:special_events) { create_list(:special_event, 3, restaurant: restaurant) }
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'returns a list of special events for the restaurant' do
        get :index
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body).length).to eq(3)
      end
    end
    
    context 'as a regular user' do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end
      
      it 'returns forbidden' do
        get :index
        
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
  
  describe 'GET #show' do
    let(:special_event) { create(:special_event, restaurant: restaurant) }
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'returns the special event' do
        get :show, params: { id: special_event.id }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['id']).to eq(special_event.id)
      end
    end
  end
  
  describe 'POST #create' do
    let(:valid_params) do
      {
        description: 'Test Special Event',
        event_date: Date.tomorrow.to_s,
        start_time: '10:00',
        end_time: '18:00',
        vip_only_checkout: true,
        code_prefix: 'TEST'
      }
    end
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'creates a new special event' do
        expect {
          post :create, params: { special_event: valid_params }
        }.to change(SpecialEvent, :count).by(1)
        
        expect(response).to have_http_status(:created)
        
        event = JSON.parse(response.body)
        expect(event['description']).to eq('Test Special Event')
        expect(event['vip_only_checkout']).to be true
        expect(event['code_prefix']).to eq('TEST')
      end
    end
  end
  
  describe 'PATCH #update' do
    let(:special_event) { create(:special_event, restaurant: restaurant) }
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'updates the special event' do
        patch :update, params: { 
          id: special_event.id, 
          special_event: { 
            description: 'Updated Event',
            vip_only_checkout: true
          } 
        }
        
        expect(response).to have_http_status(:success)
        
        special_event.reload
        expect(special_event.description).to eq('Updated Event')
        expect(special_event.vip_only_checkout).to be true
      end
    end
  end
  
  describe 'DELETE #destroy' do
    let!(:special_event) { create(:special_event, restaurant: restaurant) }
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'deletes the special event' do
        expect {
          delete :destroy, params: { id: special_event.id }
        }.to change(SpecialEvent, :count).by(-1)
        
        expect(response).to have_http_status(:no_content)
      end
    end
  end
  
  describe 'POST #set_as_current' do
    let(:special_event) { create(:special_event, restaurant: restaurant) }
    
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
    end
  end
end
