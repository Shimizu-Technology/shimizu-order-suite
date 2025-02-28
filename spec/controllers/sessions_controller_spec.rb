require 'rails_helper'

RSpec.describe SessionsController, type: :controller do
  describe 'POST #create' do
    let(:user) { create(:user, password: 'password123') }
    
    context 'with valid credentials' do
      let(:valid_credentials) do
        {
          email: user.email,
          password: 'password123'
        }
      end
      
      it 'returns a success response with the user' do
        post :create, params: valid_credentials
        expect(response).to have_http_status(:ok)
        expect(json_response[:user][:id]).to eq(user.id)
        expect(json_response[:user][:email]).to eq(user.email)
        expect(json_response[:user][:first_name]).to eq(user.first_name)
        expect(json_response[:user][:last_name]).to eq(user.last_name)
        expect(json_response[:user]).not_to include(:password_digest)
      end
      
      it 'returns a JWT token' do
        post :create, params: valid_credentials
        expect(json_response[:token]).to be_present
      end
    end
    
    context 'with invalid credentials' do
      let(:invalid_credentials) do
        {
          email: user.email,
          password: 'wrong_password'
        }
      end
      
      it 'returns an unauthorized response' do
        post :create, params: invalid_credentials
        expect(response).to have_http_status(:unauthorized)
        expect(json_response[:error]).to eq('Invalid email or password')
      end
    end
    
    context 'with non-existent user' do
      let(:non_existent_credentials) do
        {
          email: 'nonexistent@example.com',
          password: 'password123'
        }
      end
      
      it 'returns an unauthorized response' do
        post :create, params: non_existent_credentials
        expect(response).to have_http_status(:unauthorized)
        expect(json_response[:error]).to eq('Invalid email or password')
      end
    end
  end
  
  describe 'DELETE #destroy' do
    let(:user) { create(:user) }
    let(:token) { JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base) }
    
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'returns a success response' do
        delete :destroy
        expect(response).to have_http_status(:ok)
        expect(json_response[:message]).to eq('Logged out successfully')
      end
      
      # Note: In a real implementation, you might have a token blacklist or other mechanism
      # to invalidate tokens. If that's the case, you should test that functionality here.
    end
    
    context 'when not authenticated' do
      it 'returns unauthorized' do
        delete :destroy
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
  
  describe 'GET #validate' do
    let(:user) { create(:user) }
    let(:token) { JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base) }
    
    context 'with valid token' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end
      
      it 'returns the current user' do
        get :validate
        expect(response).to have_http_status(:ok)
        expect(json_response[:user][:id]).to eq(user.id)
        expect(json_response[:user][:email]).to eq(user.email)
        expect(json_response[:user][:first_name]).to eq(user.first_name)
        expect(json_response[:user][:last_name]).to eq(user.last_name)
      end
    end
    
    context 'with invalid token' do
      before do
        request.headers['Authorization'] = "Bearer invalid_token"
      end
      
      it 'returns unauthorized' do
        get :validate
        expect(response).to have_http_status(:unauthorized)
      end
    end
    
    context 'without token' do
      it 'returns unauthorized' do
        get :validate
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
