class FixCashPaymentTypes < ActiveRecord::Migration[6.1]
  def up
    # Find all cash payments that are marked as "additional" and are the only payment for an order
    orders_with_single_additional_cash_payment = execute(<<-SQL).to_a.map { |row| row['order_id'] }
      SELECT order_id
      FROM order_payments
      WHERE payment_method = 'cash' AND payment_type = 'additional'
      GROUP BY order_id
      HAVING COUNT(order_id) = 1
    SQL
    
    # Log the number of orders that will be updated
    puts "Found #{orders_with_single_additional_cash_payment.size} orders with a single additional cash payment"
    
    # Update these payments to be "initial" instead of "additional"
    if orders_with_single_additional_cash_payment.any?
      # First, get the payments that need to be updated
      payments_to_update = execute(<<-SQL).to_a
        SELECT id, order_id, amount, transaction_id, cash_received, change_due, description
        FROM order_payments
        WHERE order_id IN (#{orders_with_single_additional_cash_payment.join(',')})
          AND payment_method = 'cash'
          AND payment_type = 'additional'
      SQL
      
      # Update each payment individually to properly set payment_details
      payments_to_update.each do |payment|
        # Extract cash_received and change_due
        cash_received = payment['cash_received'] || payment['amount']
        change_due = payment['change_due'] || 0
        
        # Create payment_details JSON
        payment_details = {
          payment_method: 'cash',
          transaction_id: payment['transaction_id'],
          payment_date: Time.now.strftime('%Y-%m-%d'),
          notes: "Cash payment - Received: $#{cash_received.to_f.round(2)}, Change: $#{change_due.to_f.round(2)}",
          cash_received: cash_received,
          change_due: change_due,
          status: 'succeeded'
        }.to_json
        
        # Update the payment
        execute(<<-SQL)
          UPDATE order_payments
          SET payment_type = 'initial',
              description = 'Initial cash payment' || SUBSTRING(description FROM POSITION('with change' IN description)),
              payment_details = '#{payment_details}'
          WHERE id = #{payment['id']}
        SQL
      end
      
      # Log the number of records updated
      puts "Updated #{payments_to_update.size} cash payments from 'additional' to 'initial' with payment details"
    else
      puts "No cash payments to update"
    end
  end
  
  def down
    # This migration is not reversible as we can't determine which were originally "additional"
    raise ActiveRecord::IrreversibleMigration
  end
end