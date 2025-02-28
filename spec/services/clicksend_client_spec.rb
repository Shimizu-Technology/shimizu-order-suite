require 'rails_helper'

RSpec.describe ClicksendClient, type: :service do
  let(:client) { ClicksendClient.new }
  let(:phone_number) { '+15551234567' }
  let(:message) { 'Test message' }
  
  describe '#initialize' do
    it 'sets up the client with API credentials' do
      expect(client.instance_variable_get(:@username)).not_to be_nil
      expect(client.instance_variable_get(:@api_key)).not_to be_nil
    end
  end
  
  describe '#send_sms' do
    context 'when successful' do
      before do
        # Stub the HTTP request
        stub_request(:post, "https://rest.clicksend.com/v3/sms/send")
          .with(
            headers: {
              'Authorization' => /Basic .+/,
              'Content-Type' => 'application/json'
            },
            body: {
              messages: [
                {
                  source: 'ruby',
                  body: message,
                  to: phone_number
                }
              ]
            }.to_json
          )
          .to_return(
            status: 200,
            body: {
              http_code: 200,
              response_code: 'SUCCESS',
              response_msg: 'Messages queued for delivery',
              data: {
                total_price: 0.05,
                total_count: 1,
                queued_count: 1,
                messages: [
                  {
                    message_id: 'ABCD1234',
                    status: 'SUCCESS'
                  }
                ]
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end
      
      it 'sends an SMS message' do
        response = client.send_sms(phone_number, message)
        expect(response).to be_a(Hash)
        expect(response[:success]).to be true
        expect(response[:message_id]).to eq('ABCD1234')
      end
    end
    
    context 'when API returns an error' do
      before do
        stub_request(:post, "https://rest.clicksend.com/v3/sms/send")
          .to_return(
            status: 400,
            body: {
              http_code: 400,
              response_code: 'ERROR',
              response_msg: 'Invalid phone number',
              data: {}
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end
      
      it 'returns an error response' do
        response = client.send_sms(phone_number, message)
        expect(response).to be_a(Hash)
        expect(response[:success]).to be false
        expect(response[:error]).to eq('Invalid phone number')
      end
    end
    
    context 'when HTTP request fails' do
      before do
        stub_request(:post, "https://rest.clicksend.com/v3/sms/send")
          .to_raise(StandardError.new('Connection error'))
      end
      
      it 'returns an error response' do
        response = client.send_sms(phone_number, message)
        expect(response).to be_a(Hash)
        expect(response[:success]).to be false
        expect(response[:error]).to eq('Connection error')
      end
    end
  end
  
  describe '#format_phone_number' do
    it 'adds + prefix if missing' do
      expect(client.send(:format_phone_number, '15551234567')).to eq('+15551234567')
    end
    
    it 'keeps + prefix if present' do
      expect(client.send(:format_phone_number, '+15551234567')).to eq('+15551234567')
    end
    
    it 'removes non-digit characters except +' do
      expect(client.send(:format_phone_number, '+1 (555) 123-4567')).to eq('+15551234567')
    end
    
    it 'handles nil input' do
      expect(client.send(:format_phone_number, nil)).to be_nil
    end
    
    it 'handles empty string input' do
      expect(client.send(:format_phone_number, '')).to eq('')
    end
  end
end
