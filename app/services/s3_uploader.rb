# app/services/s3_uploader.rb
require 'aws-sdk-s3'

class S3Uploader
  # Uploads the file to S3, returning the public URL
  def self.upload(file, filename)
    Rails.logger.info "=== S3Uploader.upload ==="
    puts "=== S3Uploader.upload ==="
    Rails.logger.info "AWS_REGION: #{ENV['AWS_REGION'].inspect}"
    puts "AWS_REGION: #{ENV['AWS_REGION'].inspect}"
    Rails.logger.info "AWS_BUCKET: #{ENV['AWS_BUCKET'].inspect}"
    puts "AWS_BUCKET: #{ENV['AWS_BUCKET'].inspect}"
    Rails.logger.info "AWS_ACCESS_KEY_ID: #{ENV['AWS_ACCESS_KEY_ID']&.slice(0,4)}****"
    puts "AWS_ACCESS_KEY_ID: #{ENV['AWS_ACCESS_KEY_ID']&.slice(0,4)}****"

    Rails.logger.info "file path: #{file.path.inspect}"
    puts "file path: #{file.path.inspect}"
    Rails.logger.info "filename: #{filename.inspect}"
    puts "filename: #{filename.inspect}"

    s3 = Aws::S3::Resource.new(
      region: ENV['AWS_REGION'],
      credentials: Aws::Credentials.new(
        ENV['AWS_ACCESS_KEY_ID'],
        ENV['AWS_SECRET_ACCESS_KEY']
      )
    )

    bucket_name = ENV['AWS_BUCKET']
    Rails.logger.info "bucket_name => #{bucket_name.inspect}"
    puts "bucket_name => #{bucket_name.inspect}"

    # sanitize the filename just to be safe
    safe_filename = filename.strip.gsub(/[^\w.\-]/, '_')
    Rails.logger.info "safe_filename => #{safe_filename.inspect}"
    puts "safe_filename => #{safe_filename.inspect}"

    obj = s3.bucket(bucket_name).object(safe_filename)
    Rails.logger.info "S3 object key => #{obj.key.inspect}"
    puts "S3 object key => #{obj.key.inspect}"

    obj.upload_file(file.path)
    public_url = obj.public_url
    Rails.logger.info "public_url => #{public_url.inspect}"
    puts "public_url => #{public_url.inspect}"

    public_url
  end

  # Optional: remove an old file by its S3 key
  def self.delete(filename)
    Rails.logger.info "=== S3Uploader.delete ==="
    puts "=== S3Uploader.delete ==="
    Rails.logger.info "Deleting => #{filename.inspect}"
    puts "Deleting => #{filename.inspect}"

    s3 = Aws::S3::Resource.new(
      region: ENV['AWS_REGION'],
      credentials: Aws::Credentials.new(
        ENV['AWS_ACCESS_KEY_ID'],
        ENV['AWS_SECRET_ACCESS_KEY']
      )
    )

    bucket_name = ENV['AWS_BUCKET']
    Rails.logger.info "bucket_name => #{bucket_name.inspect}"
    puts "bucket_name => #{bucket_name.inspect}"

    safe_filename = filename.strip.gsub(/[^\w.\-]/, '_')
    Rails.logger.info "safe_filename => #{safe_filename.inspect}"
    puts "safe_filename => #{safe_filename.inspect}"

    obj = s3.bucket(bucket_name).object(safe_filename)
    if obj.exists?
      Rails.logger.info "Object exists, deleting now."
      puts "Object exists, deleting now."
      obj.delete
    else
      Rails.logger.info "Object does not exist => #{safe_filename}"
      puts "Object does not exist => #{safe_filename}"
    end
  end
end
