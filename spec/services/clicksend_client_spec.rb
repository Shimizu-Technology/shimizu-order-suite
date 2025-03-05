require 'rails_helper'

RSpec.describe ClicksendClient do
  describe '.send_text_message' do
    let(:to) { '+16714830219' }
    let(:body) { 'Test message' }
    let(:from) { 'Hafaloha' }
    let(:username) { 'test_username' }
    let(:api_key) { 'test_api_key' }
    let(:approved_sender_id) { 'TestSender' }
    
    before do
      allow(ENV).to receive(:[]).with('CLICKSEND_USERNAME').and_return(username)
      allow(ENV).to receive(:[]).with('CLICKSEND_API_KEY').and_return(api_key)
      allow(ENV).to receive(:[]).with('CLICKSEND_APPROVED_SENDER_ID').and_return(approved_sender_id)
      
      # Mock the HTTP request
      @http_mock = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).and_return(@http_mock)
      allow(@http_mock).to receive(:use_ssl=)
      
      @request_mock = instance_double(Net::HTTP::Post)
      allow(Net::HTTP::Post).to receive(:new).and_return(@request_mock)
      allow(@request_mock).to receive(:body=)
    end
    
    context 'when the API call is successful' do
      let(:success_response) do
        instance_double(
          Net::HTTPResponse,
          code: '200',
          body: {
            response_code: 'SUCCESS',
            data: {
              messages: [
                {
                  message_id: 'msg123',
                  status: 'SUCCESS'
                }
              ]
            }
          }.to_json
        )
      end
      
      before do
        allow(@http_mock).to receive(:request).with(@request_mock).and_return(success_response)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:debug)
        allow(Rails.logger).to receive(:warn)
      end
      
      it 'sends an SMS message with the correct parameters' do
        # Mock the Net::HTTP::Post.new method with headers
        headers = {
          'Authorization' => "Basic #{Base64.strict_encode64("#{username}:#{api_key}")}",
          'Content-Type' => 'application/json'
        }
        allow(Net::HTTP::Post).to receive(:new).with(anything, headers).and_return(@request_mock)
        
        result = ClicksendClient.send_text_message(to: to, body: body, from: from)
        
        # Verify request body
        expected_payload = {
          messages: [
            {
              source: 'ruby_app',
              from: from,
              body: body,
              to: to
            }
          ]
        }
        expect(@request_mock).to have_received(:body=).with(expected_payload.to_json)
        
        # Verify SSL was enabled
        expect(@http_mock).to have_received(:use_ssl=).with(true)
        
        # Verify the result
        expect(result).to be true
        expect(Rails.logger).to have_received(:info).with(/Sent SMS to/)
      end
      
      it 'formats phone numbers to E.164 format' do
        unformatted_number = '6714830219' # Missing the + prefix
        
        ClicksendClient.send_text_message(to: unformatted_number, body: body, from: from)
        
        # Extract the payload from the request
        payload_json = nil
        expect(@request_mock).to have_received(:body=) do |arg|
          payload_json = arg
        end
        
        payload = JSON.parse(payload_json)
        expect(payload['messages'][0]['to']).to eq('+6714830219')
      end
      
      it 'uses the approved sender ID when from is not provided' do
        ClicksendClient.send_text_message(to: to, body: body)
        
        # Extract the payload from the request
        payload_json = nil
        expect(@request_mock).to have_received(:body=) do |arg|
          payload_json = arg
        end
        
        payload = JSON.parse(payload_json)
        expect(payload['messages'][0]['from']).to eq(approved_sender_id)
      end
      
      it 'truncates the from field if it exceeds 11 characters' do
        long_sender = 'ThisIsTooLongForClickSend'
        
        ClicksendClient.send_text_message(to: to, body: body, from: long_sender)
        
        # Extract the payload from the request
        payload_json = nil
        expect(@request_mock).to have_received(:body=) do |arg|
          payload_json = arg
        end
        
        payload = JSON.parse(payload_json)
        expect(payload['messages'][0]['from']).to eq('ThisIsTooLo')
        expect(Rails.logger).to have_received(:warn).with(/too long/)
      end
      
      it 'replaces $ with USD in the message body' do
        message_with_dollars = 'Your total is $25.99'
        
        ClicksendClient.send_text_message(to: to, body: message_with_dollars, from: from)
        
        # Extract the payload from the request
        payload_json = nil
        expect(@request_mock).to have_received(:body=) do |arg|
          payload_json = arg
        end
        
        payload = JSON.parse(payload_json)
        expect(payload['messages'][0]['body']).to eq('Your total is USD 25.99')
      end
    end
    
    context 'when the API call fails' do
      let(:error_response) do
        instance_double(
          Net::HTTPResponse,
          code: '400',
          body: {
            response_code: 'ERROR',
            response_msg: 'Invalid recipient'
          }.to_json
        )
      end
      
      before do
        allow(@http_mock).to receive(:request).with(@request_mock).and_return(error_response)
        allow(Rails.logger).to receive(:error)
      end
      
      it 'logs the error and returns false' do
        result = ClicksendClient.send_text_message(to: to, body: body, from: from)
        
        expect(result).to be false
        expect(Rails.logger).to have_received(:error).with(/HTTP Error code=400/)
      end
    end
    
    context 'when the API returns a non-success response code' do
      let(:non_success_response) do
        instance_double(
          Net::HTTPResponse,
          code: '200',
          body: {
            response_code: 'FAILED',
            response_msg: 'Message failed to send'
          }.to_json
        )
      end
      
      before do
        allow(@http_mock).to receive(:request).with(@request_mock).and_return(non_success_response)
        allow(Rails.logger).to receive(:error)
      end
      
      it 'logs the error and returns false' do
        result = ClicksendClient.send_text_message(to: to, body: body, from: from)
        
        expect(result).to be false
        expect(Rails.logger).to have_received(:error).with(/Error response:/)
      end
    end
    
    context 'when an exception occurs during the API call' do
      before do
        allow(@http_mock).to receive(:request).with(@request_mock).and_raise(StandardError.new('Connection error'))
        allow(Rails.logger).to receive(:error)
      end
      
      it 'logs the error and returns false' do
        result = ClicksendClient.send_text_message(to: to, body: body, from: from)
        
        expect(result).to be false
        expect(Rails.logger).to have_received(:error).with(/HTTP request failed: Connection error/)
      end
    end
    
    context 'when credentials are missing' do
      before do
        allow(ENV).to receive(:[]).with('CLICKSEND_USERNAME').and_return(nil)
        allow(ENV).to receive(:[]).with('CLICKSEND_API_KEY').and_return(nil)
        allow(Rails.logger).to receive(:error)
        allow(@http_mock).to receive(:request).with(@request_mock)
      end
      
      it 'logs the error and returns false without making an API call' do
        result = ClicksendClient.send_text_message(to: to, body: body, from: from)
        
        expect(result).to be false
        expect(Rails.logger).to have_received(:error).with(/Missing ClickSend credentials/)
        expect(@http_mock).not_to have_received(:request)
      end
    end
  end
end
