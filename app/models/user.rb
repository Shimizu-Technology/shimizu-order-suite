# app/models/user.rb

require "securerandom"
require "digest"

class User < ApplicationRecord
  # The User model is special in multi-tenant context
  # Super admin users might not be associated with a specific restaurant
  # So we keep the restaurant association optional but add validation in a custom method
  belongs_to :restaurant, optional: true
  
  # Custom validation for restaurant_id based on role
  validate :validate_restaurant_association
  
  # Override default scope to handle super_admin users without restaurant context
  default_scope { with_restaurant_scope }
  
  # Method to scope by current restaurant if applicable, with special handling for super_admin
  def self.with_restaurant_scope
    if ApplicationRecord.current_restaurant && column_names.include?("restaurant_id")
      # For queries, we want to include both users from the current restaurant
      # and super_admin users that might not have a restaurant_id
      where("restaurant_id = ? OR (role = 'super_admin' AND restaurant_id IS NULL)", 
            ApplicationRecord.current_restaurant.id)
    else
      all
    end
  end

  # Add associations for order acknowledgments
  has_many :order_acknowledgments, dependent: :destroy
  has_many :acknowledged_orders, through: :order_acknowledgments, source: :order
  
  # Staff member association
  has_one :staff_member, dependent: :nullify
  
  # Orders created by this user
  has_many :created_orders, class_name: 'Order', foreign_key: 'created_by_user_id', dependent: :nullify

  has_secure_password

  attr_accessor :skip_password_validation

  # Email validations
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  # We only require :password_digest presence if we're not skipping password validation
  validates :password_digest, presence: true, unless: :skip_password_validation

  validates :first_name, presence: true
  validates :last_name,  presence: true

  before_save :downcase_email

  # -----------------------------------------------------------
  # PHONE VERIFICATION FIELDS:
  # phone_verified (boolean),
  # verification_code (string),
  # verification_code_sent_at (datetime)
  # -----------------------------------------------------------

  def full_name
    "#{first_name} #{last_name}".strip
  end

  # Role validation
  validates :role, inclusion: { in: %w[super_admin admin staff customer] }

  # Role helper methods
  def super_admin?
    role == "super_admin"
  end
  
  def admin?
    role == "admin"
  end
  
  def staff?
    role == "staff"
  end
  
  def customer?
    role == "customer"
  end
  
  def admin_or_above?
    role.in?(["admin", "super_admin"])
  end
  
  def staff_or_above?
    role.in?(["staff", "admin", "super_admin"])
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

  def downcase_email
    self.email = email.downcase
  end
  
  # Validate restaurant association based on role
  def validate_restaurant_association
    # Super admin users can exist without a restaurant association
    # All other user types must be associated with a restaurant
    if role != 'super_admin' && restaurant_id.blank?
      errors.add(:restaurant_id, "must be present for non-super_admin users")
    end
  end
end
