# app/models/user.rb
class User < ApplicationRecord
  belongs_to :restaurant, optional: true

  # If you still need local passwords for staff, keep this:
  has_secure_password

  validates :email, presence: true, uniqueness: true

  # If the user is purely Auth0-based, you can skip the password presence validations
  # But if staff logs in with local credentials, keep them.
  
  # For linking with Auth0
  # e.g. validates :auth0_sub, uniqueness: true, allow_nil: true

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def admin?
    role == 'admin'
  end
end
