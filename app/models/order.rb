# app/models/order.rb

class Order < ApplicationRecord
  # Order status constants
  STATUS_PENDING = 'pending'
  STATUS_PREPARING = 'preparing'
  STATUS_READY = 'ready'
  STATUS_COMPLETED = 'completed'
  STATUS_CANCELLED = 'cancelled'
  STATUS_REFUNDED = 'refunded'
  STATUS_PARTIALLY_REFUNDED = 'partially_refunded'
  
  # Valid order statuses
  VALID_STATUSES = [
    STATUS_PENDING,
    STATUS_PREPARING,
    STATUS_READY,
    STATUS_COMPLETED,
    STATUS_CANCELLED,
    STATUS_REFUNDED,
    STATUS_PARTIALLY_REFUNDED
  ]
  
  has_many :order_payments, dependent: :destroy
  
  # Payment helper methods
  def initial_payment
    # First try to find an existing initial payment
    payment = order_payments.find_by(payment_type: 'initial')
    
    # If no initial payment exists but we have payment info in the order table,
    # create a new OrderPayment record based on the order's payment fields
    if payment.nil? && payment_method.present? && payment_amount.present? && payment_amount.to_f > 0
      payment_status_for_record = payment_status == 'paid' || payment_status == 'completed' ? 'paid' : payment_status
      
      # For Stripe payments, ensure payment_id starts with 'pi_' for test mode
      payment_id_to_use = payment_id
      if payment_method == 'stripe' && payment_id.present? && !payment_id.start_with?('pi_')
        # Check if we're in test mode
        test_mode = restaurant.admin_settings&.dig('payment_gateway', 'test_mode')
        if test_mode
          # Generate a Stripe-like payment intent ID for test mode
          payment_id_to_use = "pi_test_#{SecureRandom.hex(16)}"
          Rails.logger.info("Generated test mode payment_id: #{payment_id_to_use} for order #{id}")
        end
      end
      
      payment = order_payments.create(
        payment_type: 'initial',
        amount: payment_amount,
        payment_method: payment_method,
        status: payment_status_for_record,
        transaction_id: transaction_id || payment_id_to_use,
        payment_id: payment_id_to_use || payment_id,
        description: "Initial payment"
      )
      Rails.logger.info("Created initial payment record for order #{id}: #{payment.inspect}")
    end
    
    payment
  end
  
  def additional_payments
    order_payments.where(payment_type: 'additional')
  end
  
  def refunds
    order_payments.where(payment_type: 'refund')
  end
  
  def total_paid
    order_payments.where(status: 'paid', payment_type: ['initial', 'additional']).sum(:amount)
  end
  
  def total_refunded
    order_payments.where(payment_type: 'refund', status: 'completed').sum(:amount)
  end
  
  def net_amount
    total_paid - total_refunded
  end
  
  # Refund status helper methods
  def refunded?
    status == STATUS_REFUNDED
  end
  
  def partially_refunded?
    status == STATUS_PARTIALLY_REFUNDED
  end
  
  def has_refunds?
    refunded? || partially_refunded? || total_refunded > 0
  end
  
  def update_refund_status
    if total_refunded > 0
      if (total_paid - total_refunded).abs < 0.01
        # Full refund (allowing for small floating point differences)
        update(payment_status: STATUS_REFUNDED, status: STATUS_REFUNDED)
      else
        # Partial refund
        update(payment_status: STATUS_PARTIALLY_REFUNDED, status: STATUS_PARTIALLY_REFUNDED)
      end
    end
  end
  
  # Virtual attribute for VIP code (not stored in database)
  attr_accessor :vip_code
  # Default scope to current restaurant
  default_scope { with_restaurant_scope }
  belongs_to :restaurant
  belongs_to :user, optional: true
  belongs_to :vip_access_code, optional: true
  
  # Add associations for order acknowledgments
  has_many :order_acknowledgments, dependent: :destroy
  has_many :acknowledging_users, through: :order_acknowledgments, source: :user

  # AUTO-SET pickup time if not provided
  before_save :set_default_pickup_time
  
  # Store vip_code in the database column if provided
  before_save :store_vip_code

  # After creation, enqueue a background job for WhatsApp notifications
  after_create :notify_whatsapp

  # Convert total to float, add created/updated times, plus userId & contact info
  def as_json(options = {})
    super(options).merge(
      'total' => total.to_f,
      'createdAt' => created_at.iso8601,
      'updatedAt' => updated_at.iso8601,
      'userId' => user_id,

      # Provide an ISO8601 string for JS
      'estimatedPickupTime' => estimated_pickup_time&.iso8601,

      # Contact fields
      'contact_name' => contact_name,
      'contact_phone' => contact_phone,
      'contact_email' => contact_email,
      
      # Add flag for orders requiring 24-hour advance notice
      'requires_advance_notice' => requires_advance_notice?,
      'max_advance_notice_hours' => max_advance_notice_hours,
      
      # Payment fields
      'payment_method' => payment_method,
      'transaction_id' => transaction_id,
      'payment_status' => payment_status,
      'payment_amount' => payment_amount.to_f,
      
      # VIP code (if present)
      'vip_code' => vip_code,
      'vip_access_code_id' => vip_access_code_id,
      
      # Merchandise items (if present)
      'merchandise_items' => merchandise_items || []
    )
  end

  # Check if this order contains any items requiring advance notice (24 hours)
  def requires_advance_notice?
    max_advance_notice_hours >= 24
  end
  
  # Get the maximum advance notice hours required by any item in this order
  def max_advance_notice_hours
    @max_advance_notice_hours ||= begin
      max_hours = 0
      items.each do |item|
        menu_item = MenuItem.find_by(id: item['id'])
        if menu_item && menu_item.advance_notice_hours.to_i > max_hours
          max_hours = menu_item.advance_notice_hours.to_i
        end
      end
      max_hours
    end
  end

  private

  def set_default_pickup_time
    return unless estimated_pickup_time.blank?

    if requires_advance_notice?
      # For orders with 24-hour notice items, set pickup time to next day at 10 AM
      tomorrow = Time.current.in_time_zone(restaurant.time_zone).tomorrow
      self.estimated_pickup_time = Time.new(
        tomorrow.year, tomorrow.month, tomorrow.day, 10, 0, 0, 
        Time.find_zone(restaurant.time_zone)&.formatted_offset || "+10:00"
      )
    else
      # For regular orders, set a default of 20 minutes
      self.estimated_pickup_time = Time.current + 20.minutes
    end
  end

  def store_vip_code
    # Store the vip_code in the database column if it's provided
    self.write_attribute(:vip_code, vip_code) if vip_code.present?
  end

  def notify_whatsapp
    return if Rails.env.test?

    # Get the WhatsApp group ID from the restaurant's admin_settings
    group_id = restaurant.admin_settings&.dig('whatsapp_group_id')
    return unless group_id.present?

    # Food items
    food_item_lines = items.map do |item|
      "- #{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
    end.join("\n")
    
    # Merchandise items
    merch_item_lines = ""
    if merchandise_items.present? && merchandise_items.any?
      merch_item_lines = "\n\nMerchandise Items:\n" + merchandise_items.map do |item|
        "- #{item['name']} #{item['size']} #{item['color']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
      end.join("\n")
    end

    message_text = <<~MSG
      New order \##{id} created!

      Food Items:
      #{food_item_lines}
      #{merch_item_lines}

      Total: $#{'%.2f' % total.to_f}
      Status: #{status}

      Instructions: #{special_instructions.presence || 'none'}
    MSG

    # Instead of calling Wassenger inline, enqueue an async job:
    SendWhatsappJob.perform_later(group_id, message_text)
  end
end
