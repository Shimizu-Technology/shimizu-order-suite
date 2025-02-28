require 'rails_helper'

RSpec.describe UsersController, type: :controller do
  describe 'POST #create' do
    let(:restaurant) { create(:restaurant) }
    let(:valid_attributes) do
      {
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123',
        first_name: 'John',
        last_name: 'Doe',
        phone: '123-456-7890'
      }
    end

    let(:invalid_attributes) do
      {
        email: 'invalid-email',
        password: 'short',
        password_confirmation: 'not-matching',
        first_name: '',
        last_name: ''
      }
    end

    context 'with valid params' do
      it 'creates a new User' do
        expect {
          post :create, params: { user: valid_attributes }
        }.to change(User, :count).by(1)
      end

      it 'returns a success response with the new user' do
        post :create, params: { user: valid_attributes }
        expect(response).to have_http_status(:created)
        expect(json_response[:email]).to eq('test@example.com')
        expect(json_response[:first_name]).to eq('John')
        expect(json_response[:last_name]).to eq('Doe')
        expect(json_response[:phone]).to eq('123-456-7890')
        expect(json_response).not_to include(:password_digest)
      end

      it 'returns a JWT token' do
        post :create, params: { user: valid_attributes }
        expect(json_response[:token]).to be_present
      end
    end

    context 'with invalid params' do
      it 'does not create a new User' do
        expect {
          post :create, params: { user: invalid_attributes }
        }.not_to change(User, :count)
      end

      it 'returns an error response' do
        post :create, params: { user: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:errors]).to be_present
      end
    end
  end

  describe 'GET #show' do
    let(:user) { create(:user) }
    let(:token) { JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base) }

    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end

      it 'returns the user' do
        get :show, params: { id: user.id }
        expect(response).to have_http_status(:ok)
        expect(json_response[:id]).to eq(user.id)
        expect(json_response[:email]).to eq(user.email)
        expect(json_response[:first_name]).to eq(user.first_name)
        expect(json_response[:last_name]).to eq(user.last_name)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        get :show, params: { id: user.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT #update' do
    let(:user) { create(:user) }
    let(:token) { JWT.encode({ user_id: user.id }, Rails.application.credentials.secret_key_base) }
    let(:update_attributes) do
      {
        first_name: 'Updated',
        last_name: 'Name',
        phone: '987-654-3210'
      }
    end

    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end

      it 'updates the user' do
        put :update, params: { id: user.id, user: update_attributes }
        user.reload
        expect(user.first_name).to eq('Updated')
        expect(user.last_name).to eq('Name')
        expect(user.phone).to eq('987-654-3210')
      end

      it 'returns the updated user' do
        put :update, params: { id: user.id, user: update_attributes }
        expect(response).to have_http_status(:ok)
        expect(json_response[:first_name]).to eq('Updated')
        expect(json_response[:last_name]).to eq('Name')
        expect(json_response[:phone]).to eq('987-654-3210')
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        put :update, params: { id: user.id, user: update_attributes }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when updating another user' do
      let(:other_user) { create(:user) }
      let(:token) { JWT.encode({ user_id: other_user.id }, Rails.application.credentials.secret_key_base) }

      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end

      it 'returns forbidden' do
        put :update, params: { id: user.id, user: update_attributes }
        expect(response).to have_http_status(:forbidden)
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

      it 'destroys the user' do
        expect {
          delete :destroy, params: { id: user.id }
        }.to change(User, :count).by(-1)
      end

      it 'returns no content' do
        delete :destroy, params: { id: user.id }
        expect(response).to have_http_status(:no_content)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        delete :destroy, params: { id: user.id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when deleting another user' do
      let(:other_user) { create(:user) }
      let(:token) { JWT.encode({ user_id: other_user.id }, Rails.application.credentials.secret_key_base) }

      before do
        request.headers['Authorization'] = "Bearer #{token}"
      end

      it 'returns forbidden' do
        delete :destroy, params: { id: user.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
