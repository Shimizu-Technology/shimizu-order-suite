require 'rails_helper'

RSpec.describe PaymentsController, type: :controller do
  let(:restaurant) { create(:restaurant) }
  let(:user) { create(:user, restaurant: restaurant) }
  let(:amount) { "25.00" }
  let(:payment_method_nonce) { "fake-valid-nonce" }
  let(:transaction_id) { "transaction123" }
  let(:auth_token) { token_generator(user.id) }

  before do
    # Mock the restaurant scope
    allow(controller).to receive(:set_restaurant_scope)
    allow(controller).to receive(:public_endpoint?).and_return(true)
  end

  describe 'GET #client_token' do
    context 'when restaurant exists' do
      before do
        allow(PaymentService).to receive(:generate_client_token).and_return('test-client-token')
        allow(Restaurant).to receive(:find).with(restaurant.id.to_s).and_return(restaurant)
      end

      it 'returns a client token' do
        get :client_token, params: { restaurant_id: restaurant.id }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to include('token' => 'test-client-token')
      end

      it 'calls PaymentService.generate_client_token' do
        get :client_token, params: { restaurant_id: restaurant.id }

        expect(PaymentService).to have_received(:generate_client_token).with(restaurant)
      end
    end

    context 'when restaurant does not exist' do
      before do
        allow(Restaurant).to receive(:find).with("999").and_raise(ActiveRecord::RecordNotFound)
      end

      it 'returns a service unavailable error' do
        get :client_token, params: { restaurant_id: 999 }

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'when PaymentService raises an error' do
      before do
        allow(PaymentService).to receive(:generate_client_token).and_raise(StandardError.new('Test error'))
      end

      it 'returns a service unavailable error' do
        get :client_token, params: { restaurant_id: restaurant.id }

        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)).to include('error' => 'Failed to generate client token: Test error')
      end
    end
  end

  describe 'POST #process_payment' do
    context 'when test mode is enabled' do
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => { 'test_mode' => true }
        })
        allow(Restaurant).to receive(:find).with(restaurant.id.to_s).and_return(restaurant)
      end

      it 'returns a simulated successful response' do
        post :process_payment, params: {
          restaurant_id: restaurant.id,
          amount: amount,
          payment_method_nonce: payment_method_nonce
        }

        expect(response).to have_http_status(:ok)

        body = JSON.parse(response.body)
        expect(body['success']).to be true
        expect(body['transaction']['id']).to match(/^TEST-[a-f0-9]{20}$/)
        expect(body['transaction']['status']).to eq('authorized')
        expect(body['transaction']['amount']).to eq(amount)
      end
    end

    context 'when payment gateway is not configured' do
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => { 'test_mode' => false }
        })
        allow(Restaurant).to receive(:find).with(restaurant.id.to_s).and_return(restaurant)
      end

      it 'returns a service unavailable error' do
        post :process_payment, params: {
          restaurant_id: restaurant.id,
          amount: amount,
          payment_method_nonce: payment_method_nonce
        }

        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)).to include(
          'error' => 'Payment gateway not configured and test mode is disabled'
        )
      end
    end

    context 'when payment gateway is configured' do
      let(:transaction_result) do
        instance_double('Braintree::SuccessfulResult',
          success?: true,
          transaction: instance_double('Braintree::Transaction',
            id: transaction_id,
            status: 'authorized',
            amount: amount
          )
        )
      end

      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
            'merchant_id' => 'merchant123'
          }
        })

        allow(PaymentService).to receive(:process_payment).and_return(transaction_result)
        allow(Restaurant).to receive(:find).with(restaurant.id.to_s).and_return(restaurant)
      end

      it 'processes the payment through PaymentService' do
        post :process_payment, params: {
          restaurant_id: restaurant.id,
          amount: amount,
          payment_method_nonce: payment_method_nonce
        }

        expect(PaymentService).to have_received(:process_payment).with(
          restaurant,
          amount,
          payment_method_nonce
        )
      end

      it 'returns a successful response' do
        post :process_payment, params: {
          restaurant_id: restaurant.id,
          amount: amount,
          payment_method_nonce: payment_method_nonce
        }

        expect(response).to have_http_status(:ok)

        body = JSON.parse(response.body)
        expect(body['success']).to be true
        expect(body['transaction']['id']).to eq(transaction_id)
        expect(body['transaction']['status']).to eq('authorized')
        expect(body['transaction']['amount']).to eq(amount)
      end
    end

    context 'when payment processing fails' do
      let(:transaction_result) do
        instance_double('Braintree::ErrorResult',
          success?: false,
          message: 'Payment failed',
          errors: [ instance_double('Braintree::ValidationError', message: 'Invalid card') ]
        )
      end

      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
            'merchant_id' => 'merchant123'
          }
        })

        allow(PaymentService).to receive(:process_payment).and_return(transaction_result)
        allow(Restaurant).to receive(:find).with(restaurant.id.to_s).and_return(restaurant)
      end

      it 'returns an error response' do
        post :process_payment, params: {
          restaurant_id: restaurant.id,
          amount: amount,
          payment_method_nonce: payment_method_nonce
        }

        expect(response).to have_http_status(:unprocessable_entity)

        body = JSON.parse(response.body)
        expect(body['success']).to be false
        expect(body['message']).to eq('Payment failed')
        expect(body['errors']).to eq([ 'Invalid card' ])
      end
    end
  end

  describe 'GET #transaction' do
    context 'when authenticated' do
      before do
        request.headers['Authorization'] = "Bearer #{auth_token}"
        allow(controller).to receive(:authorize_request).and_return(true)
        allow(controller).to receive(:current_user).and_return(user)
      end

      context 'when transaction exists' do
        let(:transaction_result) do
          instance_double('Braintree::SuccessfulResult',
            success?: true,
            transaction: instance_double('Braintree::Transaction',
              id: transaction_id,
              status: 'settled',
              amount: amount,
              created_at: Time.current,
              updated_at: Time.current
            )
          )
        end

        before do
          allow(PaymentService).to receive(:find_transaction).and_return(transaction_result)
          allow(Restaurant).to receive(:find).with(restaurant.id.to_s).and_return(restaurant)
        end

        it 'returns the transaction details' do
          get :transaction, params: { restaurant_id: restaurant.id, id: transaction_id }

          expect(response).to have_http_status(:ok)

          body = JSON.parse(response.body)
          expect(body['success']).to be true
          expect(body['transaction']['id']).to eq(transaction_id)
          expect(body['transaction']['status']).to eq('settled')
        end
      end

      context 'when transaction does not exist' do
        let(:transaction_result) do
          instance_double('Braintree::ErrorResult', success?: false)
        end

        before do
          allow(PaymentService).to receive(:find_transaction).and_return(transaction_result)
          allow(Restaurant).to receive(:find).with(restaurant.id.to_s).and_return(restaurant)
        end

        it 'returns a not found error' do
          get :transaction, params: { restaurant_id: restaurant.id, id: 'invalid-id' }

          expect(response).to have_http_status(:not_found)
          expect(JSON.parse(response.body)).to include('success' => false, 'message' => 'Transaction not found')
        end
      end
    end

    context 'when not authenticated' do
      before do
        allow(controller).to receive(:authorize_request).and_call_original
      end

      it 'returns an unauthorized error' do
        get :transaction, params: { restaurant_id: restaurant.id, id: transaction_id }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
