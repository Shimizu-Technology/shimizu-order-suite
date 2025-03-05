require 'rails_helper'

RSpec.describe WassengerClient do
  let(:api_token) { 'test-api-token' }
  let(:client) { WassengerClient.new(api_token: api_token) }
  let(:group_id) { '1234567890@g.us' }
  let(:message) { 'Test WhatsApp message' }
  
  describe '#send_group_message' do
    let(:success_response) do
      instance_double(
        Net::HTTPResponse,
        code: '200',
        body: {
          id: 'msg123',
          status: 'queued',
          message: message,
          group: group_id
        }.to_json
      )
    end
    
    let(:error_response) do
      instance_double(
        Net::HTTPResponse,
        code: '400',
        body: {
          error: 'Invalid group ID'
        }.to_json
      )
    end
    
    let(:http) { instance_double(Net::HTTP) }
    let(:request) { instance_double(Net::HTTP::Post) }
    
    before do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(Net::HTTP::Post).to receive(:new).and_return(request)
      allow(request).to receive(:[]=)
      allow(request).to receive(:body=)
      allow(http).to receive(:use_ssl=)
    end
    
    context 'when the API call is successful' do
      before do
        allow(http).to receive(:request).with(request).and_return(success_response)
      end
      
      it 'sends a WhatsApp message to the specified group' do
        result = client.send_group_message(group_id, message)
        
        # Verify HTTP request was properly configured
        expect(Net::HTTP::Post).to have_received(:new)
        expect(request).to have_received(:[]=).with('Content-Type', 'application/json')
        expect(request).to have_received(:[]=).with('Token', api_token)
        
        # Verify request body
        expected_body = {
          group: group_id,
          message: message
        }.to_json
        expect(request).to have_received(:body=).with(expected_body)
        
        # Verify SSL was enabled
        expect(http).to have_received(:use_ssl=).with(true)
        
        # Verify the result
        expect(result).to be_a(Hash)
        expect(result['id']).to eq('msg123')
        expect(result['status']).to eq('queued')
      end
    end
    
    context 'when the API call fails' do
      before do
        allow(http).to receive(:request).with(request).and_return(error_response)
        allow(Rails.logger).to receive(:error)
      end
      
      it 'logs the error and returns the parsed response' do
        result = client.send_group_message(group_id, message)
        
        # Verify error was logged
        expect(Rails.logger).to have_received(:error).with(/Error sending WhatsApp message/)
        
        # Verify the result
        expect(result).to be_a(Hash)
        expect(result['error']).to eq('Invalid group ID')
      end
    end
    
    context 'when an exception occurs during the API call' do
      before do
        allow(http).to receive(:request).with(request).and_raise(StandardError.new('Connection error'))
        allow(Rails.logger).to receive(:error)
      end
      
      it 'logs the error and re-raises the exception' do
        expect {
          client.send_group_message(group_id, message)
        }.to raise_error(StandardError, 'Connection error')
      end
    end
  end
  
  describe 'initialization' do
    context 'when no API token is provided' do
      before do
        allow(ENV).to receive(:[]).with('WASSENGER_API_TOKEN').and_return('env-api-token')
      end
      
      it 'uses the API token from the environment' do
        client = WassengerClient.new
        
        # We can't directly test the instance variable, so we'll test the behavior
        # by mocking the send_group_message method and checking the token used
        
        # Mock the HTTP request
        http = instance_double(Net::HTTP)
        request = instance_double(Net::HTTP::Post)
        response = instance_double(Net::HTTPResponse, code: '200', body: '{}')
        
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(Net::HTTP::Post).to receive(:new).and_return(request)
        allow(request).to receive(:[]=)
        allow(request).to receive(:body=)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:request).with(request).and_return(response)
        
        # Call the method
        client.send_group_message(group_id, message)
        
        # Verify the token used
        expect(request).to have_received(:[]=).with('Token', 'env-api-token')
      end
    end
  end
end
