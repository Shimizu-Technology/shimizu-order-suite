# app/models/wholesale/participant.rb

module Wholesale
  class Participant < ApplicationRecord
    # Associations
    belongs_to :fundraiser, class_name: 'Wholesale::Fundraiser'
    has_many :orders, class_name: 'Wholesale::Order', dependent: :restrict_with_error
    
    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true,
                     uniqueness: { scope: :fundraiser_id, case_sensitive: false },
                     format: { with: /\A[a-z0-9-]+\z/, message: "must contain only lowercase letters, numbers, and hyphens" },
                     length: { minimum: 2, maximum: 100 }
    validates :goal_amount_cents, numericality: { greater_than: 0 }, allow_blank: true
    validates :current_amount_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :photo_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }, allow_blank: true
    
    # Custom validations
    validate :slug_cannot_be_reserved
    
    # Callbacks
    before_validation :generate_slug, if: -> { slug.blank? && name.present? }
    before_validation :normalize_slug
    before_validation :ensure_current_amount_not_nil
    
    # Scopes
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    scope :with_goals, -> { where.not(goal_amount_cents: nil) }
    scope :without_goals, -> { where(goal_amount_cents: nil) }
    scope :by_name, -> { order(:name) }
    scope :by_progress, -> { order(Arel.sql('CASE WHEN goal_amount_cents IS NULL THEN 0 ELSE (current_amount_cents::float / goal_amount_cents::float) END DESC')) }
    
    # Goal amount handling (in cents)
    def goal_amount
      return nil unless goal_amount_cents
      goal_amount_cents / 100.0
    end
    
    def goal_amount=(amount)
      if amount.nil?
        self.goal_amount_cents = nil
      elsif amount.is_a?(String) && amount.blank?
        self.goal_amount_cents = nil
      elsif amount.is_a?(String)
        self.goal_amount_cents = (amount.to_f * 100).round
      else
        self.goal_amount_cents = (amount.to_f * 100).round
      end
    end
    
    # Current amount handling (in cents)
    def current_amount
      (current_amount_cents || 0) / 100.0
    end
    
    def current_amount=(amount)
      if amount.is_a?(String)
        self.current_amount_cents = (amount.to_f * 100).round
      else
        self.current_amount_cents = (amount.to_f * 100).round
      end
    end
    
    # Goal tracking methods
    def has_goal?
      goal_amount_cents.present? && goal_amount_cents > 0
    end
    
    def goal_progress_percentage
      return 0 unless has_goal?
      return 0 if current_amount_cents <= 0
      
      percentage = (current_amount_cents.to_f / goal_amount_cents.to_f) * 100
      [percentage, 100].min.round(1)
    end
    
    def goal_remaining_cents
      return 0 unless has_goal?
      [goal_amount_cents - current_amount_cents, 0].max
    end
    
    def goal_remaining
      goal_remaining_cents / 100.0
    end
    
    def goal_achieved?
      return false unless has_goal?
      current_amount_cents >= goal_amount_cents
    end
    
    def goal_exceeded?
      return false unless has_goal?
      current_amount_cents > goal_amount_cents
    end
    
    def goal_status
      return 'no_goal' unless has_goal?
      return 'exceeded' if goal_exceeded?
      return 'achieved' if goal_achieved?
      
      progress = goal_progress_percentage
      case progress
      when 0...25
        'getting_started'
      when 25...50
        'making_progress'
      when 50...75
        'halfway_there'
      when 75...100
        'almost_there'
      else
        'achieved'
      end
    end
    
    # Statistics
    def total_orders_count
      orders.count
    end
    
    def paid_orders_count
      orders.where(status: ['paid', 'fulfilled', 'completed']).count
    end
    
    def total_raised_cents
      orders.where(status: ['paid', 'fulfilled', 'completed']).sum(:total_cents)
    end
    
    def total_raised
      total_raised_cents / 100.0
    end
    
    def average_order_value_cents
      return 0 if paid_orders_count == 0
      total_raised_cents / paid_orders_count
    end
    
    def average_order_value
      average_order_value_cents / 100.0
    end
    
    # Update current amount based on actual orders
    def recalculate_current_amount!
      new_amount = total_raised_cents
      update!(current_amount_cents: new_amount)
      new_amount
    end
    
    # URL helpers
    def to_param
      slug
    end
    
    def fundraiser_participant_url
      "/wholesale/#{fundraiser.slug}?participant=#{slug}"
    end
    
    private
    
    def generate_slug
      base_slug = name.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
      counter = 1
      potential_slug = base_slug
      
      while fundraiser.participants.where(slug: potential_slug).where.not(id: id).exists?
        potential_slug = "#{base_slug}-#{counter}"
        counter += 1
      end
      
      self.slug = potential_slug
    end
    
    def normalize_slug
      self.slug = slug&.downcase&.strip
    end
    
    def ensure_current_amount_not_nil
      self.current_amount_cents ||= 0
    end
    
    def slug_cannot_be_reserved
      reserved_slugs = %w[admin api app new edit create update destroy general organization]
      if reserved_slugs.include?(slug&.downcase)
        errors.add(:slug, 'is reserved and cannot be used')
      end
    end
  end
end