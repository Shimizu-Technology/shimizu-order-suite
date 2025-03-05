require 'rails_helper'

RSpec.describe S3Uploader do
  describe '.upload' do
    let(:file) do
      double('file', 
        original_filename: 'test_image.jpg',
        content_type: 'image/jpeg',
        read: 'fake image data',
        path: '/tmp/test_image.jpg'
      )
    end
    
    let(:filename) { 'custom_filename.jpg' }
    let(:s3_object) { double('s3_object', key: filename) }
    let(:s3_bucket) { double('s3_bucket') }
    let(:s3_resource) { double('s3_resource') }
    let(:public_url) { 'https://s3.example.com/bucket/custom_filename.jpg' }

    before do
      allow(Aws::S3::Resource).to receive(:new).and_return(s3_resource)
      allow(s3_resource).to receive(:bucket).and_return(s3_bucket)
      allow(s3_bucket).to receive(:object).with(filename).and_return(s3_object)
      allow(s3_object).to receive(:upload_file).and_return(true)
      allow(s3_object).to receive(:public_url).and_return(public_url)
      
      # Mock ENV variables
      stub_const('ENV', ENV.to_hash.merge({
        'S3_BUCKET' => 'test-bucket',
        'AWS_REGION' => 'us-west-2',
        'AWS_ACCESS_KEY_ID' => 'test-key',
        'AWS_SECRET_ACCESS_KEY' => 'test-secret'
      }))
    end

    it 'uploads the file to S3 and returns the public URL' do
      expect(S3Uploader.upload(file, filename)).to eq(public_url)
      
      # Verify S3 client was initialized with correct parameters
      expect(Aws::S3::Resource).to have_received(:new).with(
        hash_including(
          region: 'us-west-2',
          credentials: instance_of(Aws::Credentials)
        )
      )
      
      # Verify correct bucket was used
      expect(s3_resource).to have_received(:bucket).with('hafaloha')
      
      # Verify object was created with correct filename
      expect(s3_bucket).to have_received(:object).with(filename)
      
      # Verify upload_file was called with correct parameters
      expect(s3_object).to have_received(:upload_file).with(file.path)
    end

    it 'raises an error if S3 configuration is missing' do
      # Mock missing ENV variables
      stub_const('ENV', {})
      
      expect {
        S3Uploader.upload(file, filename)
      }.to raise_error(RuntimeError, /Missing S3 configuration/)
    end
  end
end
