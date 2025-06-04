# app/models/fundraiser.rb

class Fundraiser < ApplicationRecord
  # Include TenantScoped for direct restaurant association
  include TenantScoped
  
  # Associations
  belongs_to :restaurant
  has_many :fundraiser_participants, dependent: :destroy
  has_many :fundraiser_items, dependent: :destroy
  
  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: { scope: :restaurant_id }, 
            format: { with: /\A[a-z0-9\-_]+\z/, message: "only allows lowercase letters, numbers, hyphens, and underscores" }
  
  # Order code validations
  validates :order_code, presence: true
  validates :order_code, uniqueness: { scope: :restaurant_id, message: "is already in use by another fundraiser" }
  validates :order_code, format: { with: /\A[A-Z0-9]{1,6}\z/, message: "must be 1-6 alphanumeric characters" }
  validates :order_code, exclusion: { in: %w(O R RES), message: "is a reserved code" }
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :current, -> { 
    now = Time.current
    where(active: true)
      .where('(start_date IS NULL OR start_date <= ?)', now)
      .where('(end_date IS NULL OR end_date >= ?)', now)
  }
  
  # Callbacks
  before_validation :normalize_slug
  before_validation :normalize_order_code
  
  private
  
  # Convert slug to lowercase and replace spaces with hyphens
  def normalize_slug
    self.slug = slug.to_s.downcase.gsub(/\s+/, '-') if slug.present?
  end
  
  # Convert order_code to uppercase and remove any whitespace
  def normalize_order_code
    if order_code.present?
      self.order_code = order_code.to_s.upcase.gsub(/\s+/, '')
    elsif !persisted? # For new records only
      # Default to 'F' + id for new fundraisers without a code
      # Note: This is a fallback that would only apply after create
      self.order_code = "F#{id}" if id.present?
    end
  end
end
