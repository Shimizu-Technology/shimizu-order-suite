# app/models/user.rb

require 'securerandom'
require 'digest'

class User < ApplicationRecord
  belongs_to :restaurant, optional: true
  has_secure_password

  validates :email, presence: true, uniqueness: true
  validates :password_digest, presence: true
  validates :first_name, presence: true
  validates :last_name,  presence: true

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def admin?
    role == 'admin'
  end

  # -----------------------------------------
  # Password Reset Logic
  # -----------------------------------------
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

  # Optionally, if you want to limit fields in JSON:
  # def as_json(options = {})
  #   super(only: [:id, :email, :first_name, :last_name, :role, :phone])
  # end
end
