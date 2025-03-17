require 'rails_helper'

RSpec.describe SendSmsJob, type: :job do
  describe '#perform' do
    let(:phone_number) { '+16714830219' }
    let(:message_body) { 'Test message' }
    let(:sender_id) { 'Hafaloha' }

    it 'calls ClicksendClient.send_text_message with the correct parameters' do
      # Mock the ClicksendClient to avoid making actual API calls
      expect(ClicksendClient).to receive(:send_text_message).with(
        to: phone_number,
        body: message_body,
        from: sender_id
      )

      # Perform the job
      SendSmsJob.perform_now(
        to: phone_number,
        body: message_body,
        from: sender_id
      )
    end

    it 'enqueues the job' do
      # Test that the job gets enqueued
      expect {
        SendSmsJob.perform_later(
          to: phone_number,
          body: message_body,
          from: sender_id
        )
      }.to have_enqueued_job(SendSmsJob)
        .with(to: phone_number, body: message_body, from: sender_id)
        .on_queue('default')
    end

    context 'when ClicksendClient raises an error' do
      before do
        allow(ClicksendClient).to receive(:send_text_message).and_raise(StandardError.new('API error'))
      end

      it 'allows the error to propagate' do
        # The job should let the error bubble up so that ActiveJob can handle it
        # (e.g., with retries or dead letter queues)
        expect {
          SendSmsJob.perform_now(
            to: phone_number,
            body: message_body,
            from: sender_id
          )
        }.to raise_error(StandardError, 'API error')
      end
    end
  end
end
