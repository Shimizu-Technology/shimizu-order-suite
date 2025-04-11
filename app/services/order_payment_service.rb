# app/services/order_payment_service.rb
class OrderPaymentService < TenantScopedService
  attr_accessor :current_user

  # Get all payments for an order
  def list_payments(order_id)
    order = find_order_with_tenant_scope(order_id)
    return [] unless order
    
    payments = order.order_payments
    
    # Enhance payment details with created_by_user_id
    payments.map do |payment|
      payment_hash = payment.as_json
      
      # Add created_by_user_id to payment_details if not already present
      if payment_hash['payment_details'].is_a?(Hash) && !payment_hash['payment_details']['created_by_user_id']
        payment_hash['payment_details']['created_by_user_id'] = order.created_by_user_id
      end
      
      payment_hash
    end
  end

  # Get payment summary for an order
  def get_payment_summary(order_id)
    order = find_order_with_tenant_scope(order_id)
    return nil unless order
    
    {
      total_paid: order.total_paid,
      total_refunded: order.total_refunded,
      net_amount: order.net_amount
    }
  end

  # Create a new payment for an order
  def create_payment(order_id, payment_params)
    order = find_order_with_tenant_scope(order_id)
    return { success: false, errors: ["Order not found"], status: :not_found } unless order
    
    payment = order.order_payments.new(payment_params)
    
    if payment.save
      { success: true, payment: payment, status: :created }
    else
      { success: false, errors: payment.errors.full_messages, status: :unprocessable_entity }
    end
  end

  # Create an additional payment for added items
  def create_additional_payment(order_id, items, payment_method, payment_details = {})
    order = find_order_with_tenant_scope(order_id)
    return { success: false, errors: ["Order not found"], status: :not_found } unless order
    
    # Calculate the price of added items
    additional_amount = calculate_additional_amount(order, items)
    
    if additional_amount <= 0
      return { success: false, errors: ["No additional payment needed"], status: :unprocessable_entity }
    end
    
    # Handle manual payment methods (cash, stripe_reader, clover, revel, other)
    if ["cash", "stripe_reader", "clover", "revel", "other"].include?(payment_method.downcase)
      # Format staff order params if present
      if payment_details && payment_details['staffOrderParams'].present?
        staff_params = payment_details['staffOrderParams']
        
        # Convert staff params to string representation
        formatted_staff_params = {
          'is_staff_order' => staff_params['is_staff_order'].to_s == 'true' || staff_params['is_staff_order'] == true ? 'true' : 'false',
          'staff_member_id' => staff_params['staff_member_id'].to_s,
          'staff_on_duty' => staff_params['staff_on_duty'].to_s == 'true' || staff_params['staff_on_duty'] == true ? 'true' : 'false',
          'use_house_account' => staff_params['use_house_account'].to_s == 'true' || staff_params['use_house_account'] == true ? 'true' : 'false',
          'created_by_staff_id' => staff_params['created_by_staff_id'].to_s,
          'pre_discount_total' => staff_params['pre_discount_total'].to_s
        }
        
        # Replace the object with the formatted version
        payment_details['staffOrderParams'] = formatted_staff_params
      end
      
      payment = order.order_payments.create(
        payment_type: "additional",
        amount: additional_amount,
        payment_method: payment_method,
        status: payment_details["status"] || "paid",
        description: "Additional items: #{items.map { |i| "#{i[:quantity]}x #{i[:name]}" }.join(", ")}",
        transaction_id: payment_details["transaction_id"],
        payment_details: payment_details,
        cash_received: payment_details["cash_received"],
        change_due: payment_details["change_due"]
      )
      
      return { success: true, payment: payment }
    end
    
    # For standard payment processors, return the amount needed for client-side processing
    { 
      success: true, 
      additional_amount: additional_amount,
      requires_payment_processing: true
    }
  end

  # Find a payment for an order
  def find_payment(order_id, payment_id)
    order = find_order_with_tenant_scope(order_id)
    return { success: false, errors: ["Order not found"], status: :not_found } unless order
    
    payment = order.order_payments.find_by(id: payment_id)
    return { success: false, errors: ["Payment not found"], status: :not_found } unless payment
    
    { success: true, payment: payment }
  end
  
  # Process a refund for an order
  def process_refund(order_id, refund_params)
    order = find_order_with_tenant_scope(order_id)
    return { success: false, errors: ["Order not found"], status: :not_found } unless order
    
    # Additional authorization check for refunds
    unless is_admin?
      return { success: false, errors: ["Forbidden"], status: :forbidden }
    end
    
    # Create a refund payment
    refund_payment = order.order_payments.new(
      payment_type: "refund",
      amount: -refund_params[:amount].to_f.abs, # Ensure amount is negative for refunds
      payment_method: refund_params[:payment_method],
      status: "refunded",
      description: refund_params[:reason],
      transaction_id: "refund-#{SecureRandom.hex(8)}",
      payment_details: {
        refunded_by: current_user&.id,
        refund_reason: refund_params[:reason],
        original_payment_id: refund_params[:original_payment_id]
      }
    )
    
    if refund_payment.save
      { success: true, payment: refund_payment }
    else
      { success: false, errors: refund_payment.errors.full_messages, status: :unprocessable_entity }
    end
  end

  private

  # Find an order with tenant scoping
  def find_order_with_tenant_scope(id)
    scope_query(Order).find_by(id: id)
  end

  # Calculate additional amount for new items
  def calculate_additional_amount(order, items)
    return 0 unless items.present?
    
    total = 0
    
    items.each do |item|
      menu_item = scope_query(MenuItem).find_by(id: item[:menu_item_id])
      next unless menu_item
      
      quantity = item[:quantity].to_i
      price = menu_item.price.to_f
      
      total += quantity * price
    end
    
    total
  end

  # Check if the current user is an admin
  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
