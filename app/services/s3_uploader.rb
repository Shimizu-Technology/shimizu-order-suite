# app/services/s3_uploader.rb
require "aws-sdk-s3"

class S3Uploader
  # Uploads the file to S3, returning the public URL
  def self.upload(file, filename)
    Rails.logger.info "=== S3Uploader.upload ==="
    Rails.logger.info "AWS_REGION: #{ENV['AWS_REGION'].inspect}"
    Rails.logger.info "AWS_BUCKET: #{ENV['AWS_BUCKET'].inspect}"
    Rails.logger.info "AWS_ACCESS_KEY_ID: #{ENV['AWS_ACCESS_KEY_ID']&.slice(0, 4)}****"
    Rails.logger.info "file path: #{file.path.inspect}"
    Rails.logger.info "filename: #{filename.inspect}"

    # Check for required configuration
    region = ENV["AWS_REGION"]
    access_key = ENV["AWS_ACCESS_KEY_ID"]
    secret_key = ENV["AWS_SECRET_ACCESS_KEY"]
    bucket_name = ENV["AWS_BUCKET"] || ENV["S3_BUCKET"]

    if region.blank? || access_key.blank? || secret_key.blank? || bucket_name.blank?
      raise "Missing S3 configuration. Please check AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_BUCKET/S3_BUCKET environment variables."
    end

    s3 = Aws::S3::Resource.new(
      region: region,
      credentials: Aws::Credentials.new(
        access_key,
        secret_key
      )
    )
    Rails.logger.info "bucket_name => #{bucket_name.inspect}"

    # sanitize the filename just to be safe
    safe_filename = filename.strip.gsub(/[^\w.\-]/, "_")
    Rails.logger.info "safe_filename => #{safe_filename.inspect}"

    obj = s3.bucket(bucket_name).object(safe_filename)
    Rails.logger.info "S3 object key => #{obj.key.inspect}"

    obj.upload_file(file.path)
    public_url = obj.public_url
    Rails.logger.info "public_url => #{public_url.inspect}"

    public_url
  end

  # Optional: remove an old file by its S3 key
  def self.delete(filename)
    Rails.logger.info "=== S3Uploader.delete ==="
    Rails.logger.info "Deleting => #{filename.inspect}"

    # Check for required configuration
    region = ENV["AWS_REGION"]
    access_key = ENV["AWS_ACCESS_KEY_ID"]
    secret_key = ENV["AWS_SECRET_ACCESS_KEY"]
    bucket_name = ENV["AWS_BUCKET"] || ENV["S3_BUCKET"]

    if region.blank? || access_key.blank? || secret_key.blank? || bucket_name.blank?
      raise "Missing S3 configuration. Please check AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_BUCKET/S3_BUCKET environment variables."
    end

    s3 = Aws::S3::Resource.new(
      region: region,
      credentials: Aws::Credentials.new(
        access_key,
        secret_key
      )
    )
    Rails.logger.info "bucket_name => #{bucket_name.inspect}"

    safe_filename = filename.strip.gsub(/[^\w.\-]/, "_")
    Rails.logger.info "safe_filename => #{safe_filename.inspect}"

    obj = s3.bucket(bucket_name).object(safe_filename)
    if obj.exists?
      Rails.logger.info "Object exists, deleting now."
      obj.delete
    else
      Rails.logger.info "Object does not exist => #{safe_filename}"
    end
  end
end
