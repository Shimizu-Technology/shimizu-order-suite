namespace :payments do
  desc "Create OrderPayment records for historical manual transactions"
  task create_manual_payment_records: :environment do
    puts "Starting to create OrderPayment records for manual payment orders..."
    
    # Find all manual payment orders without corresponding OrderPayment records
    # Note: We exclude stripe_reader since it's already creating OrderPayment records
    manual_orders = Order.where(payment_method: ['cash', 'other', 'clover', 'revel'])
                        .where(payment_status: 'completed')
                        .where.not(status: 'canceled')
    
    total_orders = manual_orders.count
    puts "Found #{total_orders} manual payment orders to process"
    
    count = 0
    manual_orders.find_each do |order|
      # Skip if already has an OrderPayment record
      next if OrderPayment.exists?(order_id: order.id, payment_method: order.payment_method)
      
      # Create OrderPayment record with appropriate attributes based on payment method
      payment_attributes = {
        order_id: order.id,
        payment_type: 'initial',
        amount: order.payment_amount,
        payment_method: order.payment_method,
        transaction_id: order.transaction_id,
        payment_details: order.payment_details,
        status: 'paid',
        description: "#{order.payment_method.capitalize} payment",
        created_at: order.created_at,
        updated_at: order.updated_at
      }
      
      # For cash payments, add cash_received and change_due
      if order.payment_method == 'cash' && order.payment_details.is_a?(Hash)
        payment_attributes[:cash_received] = order.payment_details['cash_received'] || order.payment_amount
        payment_attributes[:change_due] = order.payment_details['change_due'] || 0
      end
      
      payment = OrderPayment.new(payment_attributes)
      
      if payment.save
        count += 1
        puts "Created payment record for Order ##{order.id}" if count % 10 == 0
      else
        puts "Failed to create payment record for Order ##{order.id}: #{payment.errors.full_messages.join(', ')}"
      end
    end
    
    # Handle refunds
    puts "\nProcessing refunds..."
    refund_orders = Order.where.not(refund_amount: [nil, 0])
                        .where(status: 'refunded')
                        .where(payment_method: ['cash', 'other', 'clover', 'revel'])
    
    total_refunds = refund_orders.count
    puts "Found #{total_refunds} manual refund orders to process"
    
    refund_count = 0
    refund_orders.find_each do |order|
      # Skip if already has a refund OrderPayment record
      next if OrderPayment.exists?(order_id: order.id, payment_type: 'refund')
      
      # Create refund attributes
      refund_attributes = {
        order_id: order.id,
        payment_type: 'refund',
        amount: order.refund_amount,
        payment_method: order.payment_method,
        transaction_id: "refund_#{order.id}_#{Time.now.to_i}",
        payment_details: { reason: order.dispute_reason },
        status: 'refunded',
        description: "Refund: #{order.dispute_reason || 'No reason provided'}",
        created_at: order.updated_at,
        updated_at: order.updated_at
      }
      
      # For cash refunds, add cash_received and change_due
      if order.payment_method == 'cash'
        refund_attributes[:cash_received] = order.refund_amount
        refund_attributes[:change_due] = 0
      end
      
      refund = OrderPayment.new(refund_attributes)
      
      if refund.save
        refund_count += 1
        puts "Created refund record for Order ##{order.id}" if refund_count % 10 == 0
      else
        puts "Failed to create refund record for Order ##{order.id}: #{refund.errors.full_messages.join(', ')}"
      end
    end
    
    puts "\nSummary:"
    puts "Created #{count} payment records out of #{total_orders} manual payment orders"
    puts "Created #{refund_count} refund records out of #{total_refunds} manual refund orders"
    puts "Done!"
  end
end