# app/models/wholesale/fundraiser.rb

module Wholesale
  class Fundraiser < ApplicationRecord
    include TenantScoped
    
    # Associations
    has_many :items, class_name: 'Wholesale::Item', dependent: :destroy
    has_many :participants, class_name: 'Wholesale::Participant', dependent: :destroy
    has_many :orders, class_name: 'Wholesale::Order', dependent: :restrict_with_error
    has_one :fundraiser_counter, class_name: 'Wholesale::FundraiserCounter', dependent: :destroy
    
    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true, 
                     uniqueness: { scope: :restaurant_id, case_sensitive: false },
                     format: { with: /\A[a-z0-9-]+\z/, message: "must contain only lowercase letters, numbers, and hyphens" },
                     length: { minimum: 3, maximum: 100 }
    validates :start_date, presence: true
    validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    
    # Custom validations
    validate :end_date_after_start_date
    validate :slug_cannot_be_reserved
    
    # Callbacks
    before_validation :generate_slug, if: -> { slug.blank? && name.present? }
    before_validation :normalize_slug
    
    # Scopes
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    # Current fundraisers: already started and not ended (or no end date)
    scope :current, -> {
      where('start_date <= ?', Date.current)
        .where('end_date IS NULL OR end_date >= ?', Date.current)
    }
    scope :upcoming, -> { where('start_date > ?', Date.current) }
    scope :past, -> { where('end_date < ?', Date.current) }
    scope :by_status, ->(status) { where(active: status == 'active') }
    
    # Instance methods
    def current?
      # If no date constraints are set, consider it current
      return true if start_date.nil? && end_date.nil?
      
      # If only start_date is set, check if we're past the start
      return Date.current >= start_date if start_date.present? && end_date.nil?
      
      # If only end_date is set, check if we're before the end
      return Date.current <= end_date if start_date.nil? && end_date.present?
      
      # If both dates are set, check if we're within the range
      Date.current >= start_date && Date.current <= end_date
    end
    
    def upcoming?
      start_date.present? && Date.current < start_date
    end
    
    def past?
      end_date.present? && Date.current > end_date
    end
    
    def status
      return 'inactive' unless active?
      return 'upcoming' if upcoming?
      return 'past' if past?
      'current'
    end
    
    def total_orders_count
      orders.count
    end
    
    def total_revenue_cents
      # All orders count as revenue since orders can only be created after payment
      orders.sum(:total_cents)
    end
    
    def to_param
      slug
    end
    
    # Image helper methods
    def has_card_image?
      card_image_url.present?
    end
    
    def has_banner_image?
      banner_url.present?
    end
    
    # Pickup helper methods
    def has_custom_pickup_location?
      pickup_location_name.present? || pickup_address.present?
    end
    
    def pickup_display_name
      pickup_location_name.presence || restaurant&.name || 'Pickup Location'
    end
    
    def pickup_display_address
      pickup_address.presence || restaurant&.address || 'Contact for address'
    end
    
    def pickup_contact_display_phone
      pickup_contact_phone.presence || contact_phone.presence || restaurant&.phone_number
    end
    
    def has_pickup_instructions?
      pickup_instructions.present?
    end
    
    def has_pickup_hours?
      pickup_hours.present?
    end
    
    private
    
    def generate_slug
      base_slug = name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
      self.slug = base_slug
    end
    
    def normalize_slug
      self.slug = slug&.downcase&.strip
    end
    
    def end_date_after_start_date
      return unless start_date && end_date
      
      if end_date <= start_date
        errors.add(:end_date, 'must be after start date')
      end
    end
    
    def slug_cannot_be_reserved
      reserved_slugs = %w[admin api app new edit create update destroy]
      if reserved_slugs.include?(slug&.downcase)
        errors.add(:slug, 'is reserved and cannot be used')
      end
    end
  end
end