require 'rails_helper'

RSpec.describe PaymentService do
  let(:restaurant) { create(:restaurant) }
  let(:amount) { "25.00" }
  let(:payment_method_nonce) { "fake-valid-nonce" }
  let(:transaction_id) { "transaction123" }

  describe '.generate_client_token' do
    context 'when test mode is enabled' do
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => { 'test_mode' => true }
        })
      end

      it 'returns a fake client token' do
        token = PaymentService.generate_client_token(restaurant)
        expect(token).to match(/^fake-client-token-[a-f0-9]{16}$/)
      end
    end

    context 'when test mode is disabled' do
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
            'payment_processor' => 'paypal',
            'client_id' => 'test-client-id',
            'client_secret' => 'test-client-secret',
            'environment' => 'sandbox'
          }
        })
      end

      it 'returns the client_id for PayPal processor' do
        token = PaymentService.generate_client_token(restaurant)
        expect(token).to eq('test-client-id')
      end
    end

    context 'when using stripe processor' do
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
            'payment_processor' => 'stripe',
            'publishable_key' => 'pk_test_123'
          }
        })
      end

      it 'returns the publishable key for Stripe processor' do
        token = PaymentService.generate_client_token(restaurant)
        expect(token).to eq('pk_test_123')
      end
    end
  end

  describe '.process_payment' do
    context 'when test mode is enabled' do
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => { 'test_mode' => true }
        })
      end

      it 'returns a simulated successful response' do
        result = PaymentService.process_payment(restaurant, payment_method_nonce)

        expect(result.success?).to be true
        expect(result.transaction.id).to match(/^TEST-[a-f0-9]{20}$/)
        expect(result.transaction.status).to eq('COMPLETED')
        expect(result.transaction.amount).to eq(payment_method_nonce)
      end
    end

    context 'when test mode is disabled with braintree' do
      let(:gateway) { instance_double(Braintree::Gateway) }
      let(:transaction_gateway) { instance_double(Braintree::TransactionGateway) }
      let(:transaction_result) { instance_double('Braintree::SuccessfulResult', success?: true) }

      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
            'payment_processor' => 'paypal',
            'environment' => 'sandbox',
            'merchant_id' => 'merchant123',
            'public_key' => 'public123',
            'private_key' => 'private123'
          }
        })

        allow(Braintree::Gateway).to receive(:new).and_return(gateway)
        allow(gateway).to receive(:transaction).and_return(transaction_gateway)
        allow(transaction_gateway).to receive(:sale).and_return(transaction_result)
      end

      it 'processes the payment through Braintree when no order_id' do
        PaymentService.process_payment(restaurant, payment_method_nonce)

        expect(transaction_gateway).to have_received(:sale).with(
          amount: payment_method_nonce,
          payment_method_nonce: payment_method_nonce,
          options: { submit_for_settlement: true }
        )
      end

      it 'returns the result from Braintree' do
        result = PaymentService.process_payment(restaurant, payment_method_nonce)
        expect(result).to eq(transaction_result)
      end
    end
  end

  describe '.find_transaction' do
    context 'when transaction ID starts with TEST-' do
      let(:test_transaction_id) { "TEST-abcdef1234567890" }

      it 'returns a simulated transaction' do
        result = PaymentService.find_transaction(restaurant, test_transaction_id)

        expect(result.success?).to be true
        expect(result.transaction.id).to eq(test_transaction_id)
        expect(result.transaction.status).to eq('COMPLETED')
      end
    end

    context 'when transaction ID is a real Braintree ID' do
      let(:gateway) { instance_double(Braintree::Gateway) }
      let(:transaction_gateway) { instance_double(Braintree::TransactionGateway) }
      let(:transaction_result) { instance_double('Braintree::SuccessfulResult', success?: true) }
      let(:short_transaction_id) { "abc123" }

      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
            'payment_processor' => 'paypal',
            'environment' => 'sandbox',
            'merchant_id' => 'merchant123',
            'public_key' => 'public123',
            'private_key' => 'private123'
          }
        })

        allow(Braintree::Gateway).to receive(:new).and_return(gateway)
        allow(gateway).to receive(:transaction).and_return(transaction_gateway)
        allow(transaction_gateway).to receive(:find).and_return(transaction_result)
      end

      it 'finds the transaction through Braintree' do
        PaymentService.find_transaction(restaurant, short_transaction_id)
        expect(transaction_gateway).to have_received(:find).with(short_transaction_id)
      end

      it 'returns the result from Braintree' do
        result = PaymentService.find_transaction(restaurant, short_transaction_id)
        expect(result).to eq(transaction_result)
      end
    end
  end
end
