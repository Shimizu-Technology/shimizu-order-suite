# app/models/order.rb

class Order < ApplicationRecord
  include Broadcastable
  
  # Define which attributes should trigger broadcasts
  broadcasts_on :status, :total, :items, :eta, :pickup_time, :is_staff_order, :staff_member_id
  # Order status constants
  STATUS_PENDING = "pending"
  STATUS_PREPARING = "preparing"
  STATUS_READY = "ready"
  STATUS_COMPLETED = "completed"
  STATUS_CANCELLED = "cancelled"
  STATUS_REFUNDED = "refunded"
  STATUS_PARTIALLY_REFUNDED = "partially_refunded"

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
  has_many :house_account_transactions, dependent: :nullify
  belongs_to :staff_member, optional: true
  belongs_to :created_by_staff, class_name: 'StaffMember', foreign_key: 'created_by_staff_id', optional: true

  # Payment helper methods
  def initial_payment
    # First try to find an existing initial payment
    payment = order_payments.find_by(payment_type: "initial")

    # If no initial payment exists but we have payment info in the order table,
    # create a new OrderPayment record based on the order's payment fields
    if payment.nil? && payment_method.present? && payment_amount.present? && payment_amount.to_f > 0
      payment_status_for_record = payment_status == "paid" || payment_status == "completed" ? "paid" : payment_status

      # For Stripe payments, ensure payment_id starts with 'pi_' for test mode
      payment_id_to_use = payment_id
      if payment_method == "stripe"
        # Check if we're in test mode
        test_mode = restaurant.admin_settings&.dig("payment_gateway", "test_mode")

        if payment_id.present?
          if !payment_id.start_with?("pi_") && test_mode
            # Generate a Stripe-like payment intent ID for test mode
            payment_id_to_use = "pi_test_#{SecureRandom.hex(16)}"
            Rails.logger.info("Generated test mode payment_id: #{payment_id_to_use} for order #{id}")
          end
        elsif test_mode
          # No payment_id but we're in test mode, generate one
          payment_id_to_use = "pi_test_#{SecureRandom.hex(16)}"
          Rails.logger.info("Generated test mode payment_id: #{payment_id_to_use} for order #{id} (no payment_id present)")
        end
      end

      # Ensure we have a valid payment_id for Stripe payments
      if payment_method == "stripe" && (payment_id_to_use.nil? || payment_id_to_use.empty?)
        # Generate a payment_id if none exists
        payment_id_to_use = "pi_#{SecureRandom.hex(16)}"
        Rails.logger.info("Generated payment_id: #{payment_id_to_use} for order #{id} (no valid payment_id)")
      end

      payment = order_payments.create(
        payment_type: "initial",
        amount: payment_amount,
        payment_method: payment_method,
        status: payment_status_for_record,
        transaction_id: transaction_id || payment_id_to_use,
        payment_id: payment_id_to_use || payment_id,
        description: "Initial payment"
      )
      Rails.logger.info("Created initial payment record for order #{id}: #{payment.inspect}")
    end

    # If payment exists but payment_id is nil, update it with the order's payment_id
    if payment && payment.payment_id.nil? && payment_id.present?
      payment.update(payment_id: payment_id)
      Rails.logger.info("Updated payment_id for order #{id} payment: #{payment.id} to #{payment_id}")
    end

    payment
  end

  def additional_payments
    order_payments.where(payment_type: "additional")
  end

  def refunds
    order_payments.where(payment_type: "refund")
  end

  def total_paid
    order_payments.where(status: "paid", payment_type: [ "initial", "additional" ]).sum(:amount)
  end

  def total_refunded
    order_payments.where(payment_type: "refund", status: "completed").sum(:amount)
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
  
  # Staff discount constants
  STAFF_ON_DUTY_DISCOUNT = 0.5  # 50% discount
  STAFF_OFF_DUTY_DISCOUNT = 0.3  # 30% discount
  
  # Staff order helper methods
  
  # Calculate the appropriate discount rate based on duty status
  def staff_discount_rate
    return 0 unless is_staff_order
    staff_on_duty ? STAFF_ON_DUTY_DISCOUNT : STAFF_OFF_DUTY_DISCOUNT
  end
  
  # Calculate the pre-discount total if not already set
  def calculate_pre_discount_total
    return pre_discount_total if pre_discount_total.present?
    
    # Sum up the price of all items
    items_total = items.sum { |item| (item['price'].to_f * item['quantity'].to_i) }
    
    # Add merchandise items if present
    merch_total = 0
    if merchandise_items.present?
      merch_total = merchandise_items.sum { |item| (item['price'].to_f * item['quantity'].to_i) }
    end
    
    items_total + merch_total
  end
  
  # Calculate the discount amount
  def discount_amount
    return 0 unless is_staff_order
    calculate_pre_discount_total * staff_discount_rate
  end
  
  # Apply staff discount to the order
  def apply_staff_discount
    return unless is_staff_order
    
    # Set the pre-discount total if not already set
    self.pre_discount_total ||= calculate_pre_discount_total
    
    # Calculate the discounted total
    discounted_total = pre_discount_total * (1 - staff_discount_rate)
    
    # Update the total
    self.total = discounted_total.round(2)
    
    # Store the pre-discount price for each item
    if items.present?
      items_with_pre_discount = items.map do |item|
        # Store the original price as pre_discount_price
        item_price = item['price'].to_f
        item.merge({
          'pre_discount_price' => item_price,
          'price' => (item_price * (1 - staff_discount_rate)).round(2)
        })
      end
      self.items = items_with_pre_discount
    end
  end
  
  # Process house account payment if needed
  def process_house_account
    return unless is_staff_order && use_house_account && staff_member.present?
    
    # Add a transaction to the staff member's house account
    transaction = staff_member.charge_order_to_house_account(self, created_by_staff)
    
    # Mark the payment as completed via house account
    self.payment_method = 'house_account'
    self.payment_status = 'completed'
    self.payment_amount = total
    
    # Generate a test transaction ID if none exists
    test_transaction_id = "TEST-#{SecureRandom.hex(8)}"
    self.transaction_id = test_transaction_id
    
    # Set detailed payment details for house account
    if payment_details.present? && payment_details['staffOrderParams'].present?
      # Extract the staff order params to be displayed properly
      staff_params = payment_details['staffOrderParams']
      
      # Format the staff order params for display - convert to a string representation
      formatted_staff_params = {
        'is_staff_order' => staff_params['is_staff_order'].to_s == 'true' || staff_params['is_staff_order'] == true ? 'true' : 'false',
        'staff_member_id' => staff_params['staff_member_id'].to_s,
        'staff_on_duty' => staff_params['staff_on_duty'].to_s == 'true' || staff_params['staff_on_duty'] == true ? 'true' : 'false',
        'use_house_account' => staff_params['use_house_account'].to_s == 'true' || staff_params['use_house_account'] == true ? 'true' : 'false',
        'created_by_staff_id' => staff_params['created_by_staff_id'].to_s,
        'pre_discount_total' => staff_params['pre_discount_total'].to_s
      }
      
      # Update payment details with formatted information - use string keys instead of symbol keys
      self.payment_details = payment_details.merge({
        'status' => 'succeeded',
        'payment_date' => Time.now.strftime('%Y-%m-%d'),
        'transaction_id' => test_transaction_id,
        'notes' => "Payment charged to #{staff_member.name}'s house account",
        'processor' => 'house_account',
        'payment_method' => 'house_account',
        'staffOrderParams' => formatted_staff_params,
        'house_account_transaction_id' => transaction.id.to_s
      })
    end
  end
  
  # Callbacks for staff orders
  before_save :apply_staff_discount, if: -> { is_staff_order && (new_record? || is_staff_order_changed? || staff_on_duty_changed?) }
  after_create :process_house_account, if: -> { is_staff_order && use_house_account }

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

  # After creation, enqueue background jobs for notifications
  after_create :notify_whatsapp
  after_create :notify_pushover
  after_create :notify_web_push

  # Convert total to float, add created/updated times, plus userId & contact info
  def as_json(options = {})
    super(options).merge(
      "total" => total.to_f,
      "createdAt" => created_at.iso8601,
      "updatedAt" => updated_at.iso8601,
      "userId" => user_id,

      # Provide an ISO8601 string for JS
      "estimatedPickupTime" => estimated_pickup_time&.iso8601,

      # Contact fields
      "contact_name" => contact_name,
      "contact_phone" => contact_phone,
      "contact_email" => contact_email,

      # Add flag for orders requiring 24-hour advance notice
      "requires_advance_notice" => requires_advance_notice?,
      "max_advance_notice_hours" => max_advance_notice_hours,

      # Payment fields
      "payment_method" => payment_method,
      "transaction_id" => transaction_id,
      "payment_status" => payment_status,
      "payment_amount" => payment_amount.to_f,
      "payment_details" => payment_details,

      # VIP code (if present)
      "vip_code" => vip_code,
      "vip_access_code_id" => vip_access_code_id,

      # Merchandise items (if present)
      "merchandise_items" => merchandise_items || [],
      
      # Acknowledgment timestamp
      "global_last_acknowledged_at" => global_last_acknowledged_at&.iso8601,
      
      # Staff order fields
      "is_staff_order" => is_staff_order,
      "staff_member_id" => staff_member_id,
      "staff_member_name" => staff_member&.name,
      "staff_on_duty" => staff_on_duty,
      "use_house_account" => use_house_account,
      "created_by_staff_id" => created_by_staff_id,
      "created_by_staff_name" => created_by_staff&.name,
      "pre_discount_total" => pre_discount_total.to_f,
      "discount_amount" => discount_amount.to_f,
      "discount_rate" => staff_discount_rate
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
        menu_item = MenuItem.find_by(id: item["id"])
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
    return if staff_created # Skip notifications for staff-created orders

    # Get the WhatsApp group ID from the restaurant's admin_settings
    group_id = restaurant.admin_settings&.dig("whatsapp_group_id")
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
  def notify_pushover
    return if Rails.env.test?
    return if staff_created # Skip notifications for staff-created orders
    
    # Format the order items for the notification
    # Format the order items for the notification
    food_item_lines = items.map do |item|
      "#{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
    end.join(", ")
    
    if merchandise_items.present? && merchandise_items.any?
      merch_list = merchandise_items.map do |item|
        "#{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
      end.join(", ")
      food_item_lines += ", " + merch_list unless merch_list.blank?
    end
    
    # Create a concise message for the notification
    message = "New Order ##{id}\n\n"
    message += "Items: #{food_item_lines}\n"
    message += "Total: $#{'%.2f' % total.to_f}\n"
    message += "Customer: #{contact_name}\n" if contact_name.present?
    message += "Phone: #{contact_phone}\n" if contact_phone.present?
    message += "\nSpecial Instructions: #{special_instructions}" if special_instructions.present?
    
    title = "New Order ##{id} - $#{'%.2f' % total.to_f}"
    
    SendPushoverNotificationJob.perform_later(
      restaurant_id,
      message,
      title: title,
      priority: 1,      # High priority to bypass quiet hours
      sound: "cashregister"
    )
  end
  
  def notify_web_push
    return if Rails.env.test?
    return if Rails.env.development? # Skip notifications in development environment
    return if staff_created # Skip notifications for staff-created orders
    return unless restaurant.web_push_enabled?
    
    # Format the order items for the notification
    food_item_lines = items.map do |item|
      "#{item['name']} (x#{item['quantity']}): $#{'%.2f' % item['price']}"
    end.join(", ")
    
    # Create the notification payload
    payload = {
      title: "New Order ##{id}",
      body: "Total: $#{'%.2f' % total.to_f} - #{food_item_lines}",
      icon: "/icons/icon-192.png",
      badge: "/icons/badge-96.png",
      tag: "new-order-#{id}",
      data: {
        url: "/admin/orders/#{id}",
        orderId: id,
        timestamp: Time.current.to_i
      },
      actions: [
        {
          action: "view",
          title: "View Order"
        },
        {
          action: "acknowledge",
          title: "Acknowledge"
        }
      ]
    }
    
    SendWebPushNotificationJob.perform_later(restaurant_id, payload)
  end
end
