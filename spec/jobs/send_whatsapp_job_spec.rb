require 'rails_helper'

RSpec.describe SendWhatsappJob, type: :job do
  describe '#perform' do
    let(:group_id) { '1234567890@g.us' }
    let(:message_text) { 'Test WhatsApp message' }
    let(:wassenger_client) { instance_double(WassengerClient) }
    
    before do
      allow(WassengerClient).to receive(:new).and_return(wassenger_client)
      allow(wassenger_client).to receive(:send_group_message).and_return({ 'id' => 'msg123', 'status' => 'queued' })
    end
    
    it 'calls WassengerClient#send_group_message with the correct parameters' do
      # Expect the client to receive the send_group_message call
      expect(wassenger_client).to receive(:send_group_message).with(group_id, message_text)
      
      # Perform the job
      SendWhatsappJob.perform_now(group_id, message_text)
    end
    
    it 'enqueues the job' do
      # Test that the job gets enqueued
      expect {
        SendWhatsappJob.perform_later(group_id, message_text)
      }.to have_enqueued_job(SendWhatsappJob)
        .with(group_id, message_text)
        .on_queue('default')
    end
    
    context 'when WassengerClient raises an error' do
      before do
        allow(wassenger_client).to receive(:send_group_message).and_raise(StandardError.new('API error'))
      end
      
      it 'allows the error to propagate' do
        # The job should let the error bubble up so that ActiveJob can handle it
        # (e.g., with retries or dead letter queues)
        expect {
          SendWhatsappJob.perform_now(group_id, message_text)
        }.to raise_error(StandardError, 'API error')
      end
    end
  end
end
