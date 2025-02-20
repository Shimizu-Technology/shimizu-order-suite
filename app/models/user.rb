# app/models/user.rb

require 'securerandom'
require 'digest'

class User < ApplicationRecord
  belongs_to :restaurant, optional: true
  has_secure_password

  # Email validations
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :password_digest, presence: true
  validates :first_name, presence: true
  validates :last_name,  presence: true

  # Optional: validate presence/format of phone if you want phone to be mandatory
  # validates :phone, presence: true, format: { with: /\A\d{7,15}\z/, message: "must be a valid phone number" }

  before_save :downcase_email

  # -----------------------------------------------------------
  # PHONE VERIFICATION FIELDS:
  #
  #   phone_verified (boolean) -> whether user’s phone is confirmed
  #   verification_code (string) -> last SMS code we sent
  #   verification_code_sent_at (datetime) -> when we sent the last code
  # -----------------------------------------------------------

  # Full name helper
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

    token_hash = Digest::SHA256.hexdigest(raw_token)
    token_hash == reset_password_token
  end

  def clear_reset_password_token!
    self.reset_password_token = nil
    self.reset_password_sent_at = nil
    save!(validate: false)
  end

  private

  # Force email to be lowercase before saving
  def downcase_email
    self.email = email.downcase
  end
end
