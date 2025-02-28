# app/models/user.rb

require 'securerandom'
require 'digest'

class User < ApplicationRecord
  belongs_to :restaurant, optional: true

  has_secure_password

  attr_accessor :skip_password_validation

  # Email validations
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  # We only require :password_digest presence if we're not skipping password validation
  validates :password_digest, presence: true, unless: :skip_password_validation

  validates :first_name, presence: true
  validates :last_name,  presence: true

  # Ensure email is downcased before validation to ensure uniqueness check works properly
  before_validation :downcase_email

  # -----------------------------------------------------------
  # PHONE VERIFICATION FIELDS:
  # phone_verified (boolean),
  # verification_code (string),
  # verification_code_sent_at (datetime)
  # -----------------------------------------------------------

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def admin?
    role == 'admin'
  end

  # -----------------------------------------------------------
  # PASSWORD RESET LOGIC (unchanged from your existing code)
  # -----------------------------------------------------------

  def generate_reset_password_token!
    raw_token = SecureRandom.hex(10)
    self.reset_password_token = Digest::SHA256.hexdigest(raw_token)
    self.reset_password_sent_at = Time.current
    save!(validate: false)
    raw_token
  end

  def reset_token_valid?(raw_token)
    return false if reset_password_token.blank?
    return false if reset_password_sent_at.blank? || reset_password_sent_at < 2.hours.ago

    # Ensure token comparison is done in a timing-safe manner
    token_hash = Digest::SHA256.hexdigest(raw_token.to_s)
    ActiveSupport::SecurityUtils.secure_compare(token_hash, reset_password_token.to_s)
  end

  def clear_reset_password_token!
    self.reset_password_token = nil
    self.reset_password_sent_at = nil
    save!(validate: false)
  end

  private

  def downcase_email
    self.email = email.to_s.downcase if email.present?
  end
end
