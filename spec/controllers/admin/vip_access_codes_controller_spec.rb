require 'rails_helper'

RSpec.describe Admin::VipAccessCodesController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:special_event) { create(:special_event, restaurant: restaurant) }
  let(:admin_user) { create(:user, restaurant: restaurant, role: 'admin') }
  let(:regular_user) { create(:user, restaurant: restaurant, role: 'user') }
  
  describe 'GET #index' do
    let!(:vip_codes) { create_list(:vip_access_code, 3, restaurant: restaurant, special_event: special_event) }
    
    context 'as an admin user' do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end
      
      it 'returns a list of VIP codes for the special event' do
        get :index, params: { special_event_id: special_event.id }
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body).length).to eq(3)
      end
    end
    
    context 'as a regular user' do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end
      
      it 'returns forbidden' do
        get :index, params: { special_event_id: special_event.id }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
  
  describe 'POST #create' do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end
    
    context 'with batch parameter' do
      it 'generates multiple individual codes' do
        expect {
          post :create, params: { 
            special_event_id: special_event.id, 
            batch: true, 
            count: 5,
            name: 'Test Individual VIP'
          }
        }.to change(VipAccessCode, :count).by(5)
        
        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body).length).to eq(5)
      end
    end
    
    context 'without batch parameter' do
      it 'generates a single group code' do
        expect {
          post :create, params: { 
            special_event_id: special_event.id, 
            name: 'Test Group VIP',
            max_uses: 10
          }
        }.to change(VipAccessCode, :count).by(1)
        
        expect(response).to have_http_status(:success)
        
        code = JSON.parse(response.body)
        expect(code['name']).to eq('Test Group VIP')
        expect(code['max_uses']).to eq(10)
        expect(code['group_id']).not_to be_nil
      end
    end
  end
  
  describe 'PATCH #update' do
    let(:vip_code) { create(:vip_access_code, restaurant: restaurant, special_event: special_event) }
    
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end
    
    it 'updates the VIP code' do
      patch :update, params: { 
        id: vip_code.id, 
        vip_code: { 
          name: 'Updated VIP Code',
          max_uses: 20,
          is_active: false
        } 
      }
      
      expect(response).to have_http_status(:success)
      
      vip_code.reload
      expect(vip_code.name).to eq('Updated VIP Code')
      expect(vip_code.max_uses).to eq(20)
      expect(vip_code.is_active).to be false
    end
  end
  
  describe 'DELETE #destroy' do
    let(:vip_code) { create(:vip_access_code, restaurant: restaurant, special_event: special_event) }
    
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end
    
    it 'deactivates the VIP code instead of deleting it' do
      delete :destroy, params: { id: vip_code.id }
      
      expect(response).to have_http_status(:no_content)
      
      vip_code.reload
      expect(vip_code.is_active).to be false
      expect(VipAccessCode.exists?(vip_code.id)).to be true
    end
  end
end
