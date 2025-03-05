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
      let(:gateway) { instance_double(Braintree::Gateway) }
      let(:client_token) { instance_double(Braintree::ClientTokenGateway) }
      
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
            'environment' => 'sandbox',
            'merchant_id' => 'merchant123',
            'public_key' => 'public123',
            'private_key' => 'private123'
          }
        })
        
        allow(Braintree::Gateway).to receive(:new).and_return(gateway)
        allow(gateway).to receive(:client_token).and_return(client_token)
        allow(client_token).to receive(:generate).and_return('real-client-token')
      end
      
      it 'creates a gateway with restaurant credentials' do
        PaymentService.generate_client_token(restaurant)
        
        expect(Braintree::Gateway).to have_received(:new).with(
          environment: :sandbox,
          merchant_id: 'merchant123',
          public_key: 'public123',
          private_key: 'private123'
        )
      end
      
      it 'returns a real client token from Braintree' do
        token = PaymentService.generate_client_token(restaurant)
        expect(token).to eq('real-client-token')
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
        result = PaymentService.process_payment(restaurant, amount, payment_method_nonce)
        
        expect(result.success?).to be true
        expect(result.transaction.id).to match(/^TEST-[a-f0-9]{20}$/)
        expect(result.transaction.status).to eq('authorized')
        expect(result.transaction.amount).to eq(amount)
      end
    end
    
    context 'when test mode is disabled' do
      let(:gateway) { instance_double(Braintree::Gateway) }
      let(:transaction_gateway) { instance_double(Braintree::TransactionGateway) }
      let(:transaction_result) { instance_double('Braintree::SuccessfulResult', success?: true) }
      
      before do
        allow(restaurant).to receive(:admin_settings).and_return({
          'payment_gateway' => {
            'test_mode' => false,
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
      
      it 'processes the payment through Braintree' do
        PaymentService.process_payment(restaurant, amount, payment_method_nonce)
        
        expect(transaction_gateway).to have_received(:sale).with(
          amount: amount,
          payment_method_nonce: payment_method_nonce,
          options: { submit_for_settlement: true }
        )
      end
      
      it 'returns the result from Braintree' do
        result = PaymentService.process_payment(restaurant, amount, payment_method_nonce)
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
        expect(result.transaction.status).to eq('settled')
      end
    end
    
    context 'when transaction ID is a real ID' do
      let(:gateway) { instance_double(Braintree::Gateway) }
      let(:transaction_gateway) { instance_double(Braintree::TransactionGateway) }
      let(:transaction_result) { instance_double('Braintree::SuccessfulResult', success?: true) }
      
      before do
        allow(Braintree::Gateway).to receive(:new).and_return(gateway)
        allow(gateway).to receive(:transaction).and_return(transaction_gateway)
        allow(transaction_gateway).to receive(:find).and_return(transaction_result)
      end
      
      it 'finds the transaction through Braintree' do
        PaymentService.find_transaction(restaurant, transaction_id)
        
        expect(transaction_gateway).to have_received(:find).with(transaction_id)
      end
      
      it 'returns the result from Braintree' do
        result = PaymentService.find_transaction(restaurant, transaction_id)
        expect(result).to eq(transaction_result)
      end
    end
  end
end
