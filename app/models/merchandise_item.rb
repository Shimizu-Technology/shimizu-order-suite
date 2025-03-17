class MerchandiseItem < ApplicationRecord
  apply_default_scope

  belongs_to :merchandise_collection
  has_many :merchandise_variants, dependent: :destroy

  # Define path to restaurant through associations for tenant isolation
  has_one :restaurant, through: :merchandise_collection

  validates :name, presence: true
  validates :base_price, numericality: { greater_than_or_equal_to: 0 }
  validates :low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true

  # Stock status enum with string values to avoid conflicts with helper methods
  # Using positional arguments instead of keyword arguments to avoid deprecation warning
  enum :stock_status, { in_stock: 0, out_of_stock: 1, low_stock: 2 }

  # Scopes for filtering
  scope :in_stock, -> { where(stock_status: :in_stock) }
  scope :out_of_stock, -> { where(stock_status: :out_of_stock) }
  scope :low_stock, -> { where(stock_status: :low_stock) }

  # Override with_restaurant_scope for indirect restaurant association
  def self.with_restaurant_scope
    if current_restaurant
      joins(:merchandise_collection).where(merchandise_collections: { restaurant_id: current_restaurant.id })
    else
      all
    end
  end

  # Get the effective low stock threshold (use default if not set)
  def actual_low_stock_threshold
    low_stock_threshold || 5 # Default to 5 if not set
  end

  # Update stock status based on variants
  def update_stock_status!
    if merchandise_variants.where("stock_quantity > 0").none?
      update(stock_status: :out_of_stock)
    elsif merchandise_variants.where("stock_quantity > 0 AND stock_quantity <= ?", actual_low_stock_threshold).any?
      update(stock_status: :low_stock)
    else
      update(stock_status: :in_stock)
    end
  end

  # Handle images - simplified to just support front and back images
  def second_image_url
    # If second_image_url column doesn't exist yet, fall back to additional_images first entry
    return self[:second_image_url] if has_attribute?(:second_image_url)

    images = self[:additional_images]
    return nil if images.nil?

    # Try to get the first additional image
    if images.is_a?(String)
      begin
        parsed = JSON.parse(images)
        parsed.first
      rescue JSON::ParserError
        nil
      end
    elsif images.is_a?(Array)
      images.first
    else
      nil
    end
  end

  def second_image_url=(value)
    if has_attribute?(:second_image_url)
      self[:second_image_url] = value
    else
      # If column doesn't exist yet, store in additional_images
      current = additional_images
      if value.nil?
        self.additional_images = []
      else
        self.additional_images = [ value ]
      end
    end
  end

  def as_json(options = {})
    result = super(options).merge(
      "base_price" => base_price.to_f,
      "image_url" => image_url,
      "stock_status" => stock_status,
      "status_note" => status_note,
      "low_stock_threshold" => actual_low_stock_threshold,
      "second_image_url" => second_image_url
    )

    # Add variants if requested
    if options[:include_variants]
      result["variants"] = merchandise_variants.map(&:as_json)
    end

    result
  end

  # Return front and back images for hover effect
  def front_image
    image_url
  end

  def back_image
    second_image_url
  end
end
