# app/services/s3_uploader.rb
require "aws-sdk-s3"

class S3Uploader
  # Uploads the file to S3, returning the public URL
  def self.upload(file, filename)
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

    # sanitize the filename just to be safe
    safe_filename = filename.strip.gsub(/[^\w.\-]/, "_")

    obj = s3.bucket(bucket_name).object(safe_filename)
    obj.upload_file(file.path)
    public_url = obj.public_url

    public_url
  end

  # Optional: remove an old file by its S3 key
  def self.delete(filename)
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

    safe_filename = filename.strip.gsub(/[^\w.\-]/, "_")

    obj = s3.bucket(bucket_name).object(safe_filename)
    if obj.exists?
      obj.delete
    end
  end
end
