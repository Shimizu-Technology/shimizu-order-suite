# app/models/user.rb
class User < ApplicationRecord
  belongs_to :restaurant, optional: true
  has_secure_password

  validates :email, presence: true, uniqueness: true
  validates :password_digest, presence: true

  # If you prefer both first & last name to be required:
  validates :first_name, presence: true
  validates :last_name, presence: true

  # For convenience, define a helper method:
  def full_name
    "#{first_name} #{last_name}".strip
  end

  def admin?
    role == 'admin'
  end
end
