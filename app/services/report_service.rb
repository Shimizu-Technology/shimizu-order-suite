# app/services/report_service.rb
class ReportService < TenantScopedService
  # GET /admin/reports/menu_items
  def menu_items_report(start_date, end_date)
    # Query to get all order items in date range
    orders = scope_query(Order)
              .includes(:order_payments, :staff_member, :created_by_staff, :created_by_user, :location)
              .where(created_at: start_date..end_date)
              .where.not(status: 'canceled')
    
    # Process orders to get item data
    item_data = {}
    category_data = {}
    detailed_item_orders = [] # NEW: Track individual order details for each item
    
    # Create a cache of menu item IDs to their categories
    menu_item_categories = {}
    
    # Special case mapping for common items that might be missing from the database
    special_case_categories = {
      'Aloha Poke' => 'Bowls',
      'Ahi Burger' => 'Burgers',
      'Build-a-Bowl' => 'Bowls'
    }
    
    orders.each do |order|
      # Get refunded items for this order
      refunded_items_data = order.refunds.flat_map do |refund|
        refund.get_refunded_items || []
      end
      
      # Create a hash of refunded quantities by item name and customizations
      refunded_quantities = {}
      refunded_items_data.each do |refunded_item|
        item_name = refunded_item["name"] || refunded_item[:name]
        customizations = refunded_item["customizations"] || refunded_item[:customizations]
        customizations_key = customizations&.to_s || ""
        unique_key = "#{item_name}|#{customizations_key}"
        
        quantity = refunded_item["quantity"] || refunded_item[:quantity] || 0
        refunded_quantities[unique_key] = (refunded_quantities[unique_key] || 0) + quantity.to_i
      end
      
      order.items.each do |item|
        item_id = item['id'].to_s
        item_name = item['name']
        quantity = item['quantity'].to_i
        price = item['price'].to_f
        customizations = item['customizations']
        
        # Create unique key for this item+customizations combination
        customizations_key = customizations&.to_s || ""
        unique_refund_key = "#{item_name}|#{customizations_key}"
        
        # Calculate net quantity after refunds
        refunded_quantity = refunded_quantities[unique_refund_key] || 0
        net_quantity = [quantity - refunded_quantity, 0].max
        
        # Skip items that have been completely refunded
        next if net_quantity <= 0
        
        # Look up the menu item's categories if not already cached
        unless menu_item_categories.key?(item_id)
          menu_item = scope_query(MenuItem).find_by(id: item_id)
          if menu_item
            # Get the categories for this menu item
            categories = menu_item.categories.pluck(:name)
            if categories.any?
              menu_item_categories[item_id] = categories.first # Use the first category for simplicity
              Rails.logger.info("Menu item #{item_id} (#{item_name}) has categories: #{categories.join(', ')}")
            else
              menu_item_categories[item_id] = 'Uncategorized'
              Rails.logger.info("Menu item #{item_id} (#{item_name}) has no categories")
            end
          else
            # Menu item not found in database
            Rails.logger.info("Menu item #{item_id} (#{item_name}) not found in database")
            
            # Check special case mapping
            if special_case_categories.key?(item_name)
              menu_item_categories[item_id] = special_case_categories[item_name]
              Rails.logger.info("Using special case category for #{item_name}: #{menu_item_categories[item_id]}")
            else
              # Try to get category from the order data as a fallback
              if item['category'].present?
                menu_item_categories[item_id] = item['category']
                Rails.logger.info("Using category from order data: #{item['category']}")
              else
                menu_item_categories[item_id] = 'Uncategorized'
                Rails.logger.info("No category found in order data, using 'Uncategorized'")
              end
            end
          end
        end
        
        # Get the category name from our cache
        category = menu_item_categories[item_id]
        
        # Create a unique key that includes customizations to handle items with different customizations separately
        unique_item_key = "#{item_id}|#{customizations_key}"
        
        # Update item stats with net quantities
        if !item_data[unique_item_key]
          item_data[unique_item_key] = {
            id: item_id.to_i,
            name: item_name,
            category: category,
            quantity_sold: 0,
            revenue: 0,
            customizations: customizations
          }
        end
        
        item_data[unique_item_key][:quantity_sold] += net_quantity
        item_data[unique_item_key][:revenue] += net_quantity * price
        
        # Update category stats with net quantities
        if !category_data[category]
          category_data[category] = {
            name: category,
            quantity_sold: 0,
            revenue: 0
          }
        end
        
        category_data[category][:quantity_sold] += net_quantity
        category_data[category][:revenue] += net_quantity * price
        
        # NEW: Add detailed order information for each item sale
        detailed_item_orders << {
          # Item information
          item_id: item_id.to_i,
          item_name: item_name,
          category: category,
          quantity: net_quantity,
          unit_price: price,
          total_price: net_quantity * price,
          customizations: customizations,
          
          # Order information
          order_id: order.id,
          order_number: order.order_number,
          order_status: order.status,
          order_total: order.total.to_f,
          payment_method: order.payment_method,
          payment_status: order.payment_status,
          created_at: order.created_at.iso8601,
          estimated_pickup_time: order.estimated_pickup_time&.iso8601,
          special_instructions: order.special_instructions,
          vip_code: order.vip_code,
          
          # Location information
          location_name: order.location&.name,
          location_address: order.location&.address,
          
          # Customer or Staff information
          is_staff_order: order.is_staff_order,
          
          # For regular customer orders
          customer_name: order.is_staff_order ? nil : order.contact_name,
          customer_phone: order.is_staff_order ? nil : order.contact_phone,
          customer_email: order.is_staff_order ? nil : order.contact_email,
          
          # For staff orders
          staff_member_name: order.is_staff_order ? order.staff_member&.name : nil,
          created_by_staff_name: order.created_by_staff&.name,
          created_by_user_name: order.created_by_user&.full_name,
          
          # Payment and refund details
          has_refunds: order.has_refunds?,
          total_refunded: order.total_refunded.to_f,
          net_amount: (order.total - order.total_refunded).to_f
        }
      end
    end
    
    # Calculate average prices
    item_data.each do |_, item|
      item[:average_price] = item[:revenue] / item[:quantity_sold] if item[:quantity_sold] > 0
    end
    
    {
      items: item_data.values,
      categories: category_data.values,
      detailed_orders: detailed_item_orders # NEW: Include detailed order information
    }
  end

  # GET /admin/reports/payment_methods
  def payment_methods_report(start_date, end_date)
    # Initialize payment data hash
    payment_data = {}
    detailed_payment_orders = [] # NEW: Track individual order details for each payment method
    
    # 1. Get payments from OrderPayment table (excluding refunds)
    # Since OrderPayment doesn't have restaurant_id, we need to join with orders and filter by restaurant_id
    payments = OrderPayment.joins(:order)
                        .includes(order: [:staff_member, :created_by_staff, :created_by_user, :location])
                        .where(orders: { restaurant_id: @restaurant.id })
                        .where(created_at: start_date..end_date)
                        .where.not(payment_type: 'refund')
    
    # Process OrderPayment records
    payments.each do |payment|
      method = payment.payment_method || 'unknown'
      order = payment.order
      
      payment_data[method] ||= {
        payment_method: method,
        count: 0,
        amount: 0.0  # Ensure this is a float
      }
      
      payment_data[method][:count] += 1
      payment_data[method][:amount] += payment.amount.to_f  # Convert to float
      
      # NEW: Add detailed order information for each payment
      detailed_payment_orders << {
        # Payment information
        payment_id: payment.id,
        payment_method: method,
        payment_amount: payment.amount.to_f,
        payment_status: payment.status,
        payment_type: payment.payment_type,
        payment_description: payment.description,
        transaction_id: payment.transaction_id,
        
        # Order information
        order_id: order.id,
        order_number: order.order_number,
        order_status: order.status,
        order_total: order.total.to_f,
        created_at: order.created_at.iso8601,
        estimated_pickup_time: order.estimated_pickup_time&.iso8601,
        special_instructions: order.special_instructions,
        vip_code: order.vip_code,
        
        # Location information
        location_name: order.location&.name,
        location_address: order.location&.address,
        
        # Customer or Staff information
        is_staff_order: order.is_staff_order,
        
        # For regular customer orders
        customer_name: order.is_staff_order ? nil : order.contact_name,
        customer_phone: order.is_staff_order ? nil : order.contact_phone,
        customer_email: order.is_staff_order ? nil : order.contact_email,
        
        # For staff orders
        staff_member_name: order.is_staff_order ? order.staff_member&.name : nil,
        created_by_staff_name: order.created_by_staff&.name,
        created_by_user_name: order.created_by_user&.full_name,
        
        # Payment and refund details
        has_refunds: order.has_refunds?,
        total_refunded: order.total_refunded.to_f,
        net_amount: (order.total - order.total_refunded).to_f,
        
        # Cash payment details
        cash_received: payment.cash_received&.to_f,
        change_due: payment.change_due&.to_f
      }
    end
    
    # 2. Get manual payments directly from Order table
    # Find orders with manual payments that don't have corresponding OrderPayment records
    # Note: We exclude stripe_reader since it's already creating OrderPayment records
    manual_payment_orders = scope_query(Order)
                              .includes(:staff_member, :created_by_staff, :created_by_user, :location)
                              .where(created_at: start_date..end_date)
                              .where(payment_method: ['cash', 'other', 'clover', 'revel'])
                              .where(payment_status: 'completed')
                              .where.not(status: ['canceled', 'refunded'])
    
    # Process manual payment orders
    manual_payment_orders.each do |order|
      # Skip if this order already has an OrderPayment record (to avoid double-counting)
      next if OrderPayment.exists?(order_id: order.id, payment_method: order.payment_method)
      
      method = order.payment_method
      
      payment_data[method] ||= {
        payment_method: method,
        count: 0,
        amount: 0.0
      }
      
      payment_data[method][:count] += 1
      payment_data[method][:amount] += order.payment_amount.to_f
      
      # NEW: Add detailed order information for manual payments
      detailed_payment_orders << {
        # Payment information (from order data)
        payment_id: nil, # No OrderPayment record for manual payments
        payment_method: method,
        payment_amount: order.payment_amount.to_f,
        payment_status: order.payment_status,
        payment_type: 'manual',
        payment_description: 'Manual payment entry',
        transaction_id: order.transaction_id,
        
        # Order information
        order_id: order.id,
        order_number: order.order_number,
        order_status: order.status,
        order_total: order.total.to_f,
        created_at: order.created_at.iso8601,
        estimated_pickup_time: order.estimated_pickup_time&.iso8601,
        special_instructions: order.special_instructions,
        vip_code: order.vip_code,
        
        # Location information
        location_name: order.location&.name,
        location_address: order.location&.address,
        
        # Customer or Staff information
        is_staff_order: order.is_staff_order,
        
        # For regular customer orders
        customer_name: order.is_staff_order ? nil : order.contact_name,
        customer_phone: order.is_staff_order ? nil : order.contact_phone,
        customer_email: order.is_staff_order ? nil : order.contact_email,
        
        # For staff orders
        staff_member_name: order.is_staff_order ? order.staff_member&.name : nil,
        created_by_staff_name: order.created_by_staff&.name,
        created_by_user_name: order.created_by_user&.full_name,
        
        # Payment and refund details
        has_refunds: order.has_refunds?,
        total_refunded: order.total_refunded.to_f,
        net_amount: (order.total - order.total_refunded).to_f,
        
        # Cash payment details (if available)
        cash_received: nil, # Not tracked for manual orders
        change_due: nil
      }
    end
    
    # 3. Handle ALL refunds from OrderPayment table
    refunds = OrderPayment.joins(:order)
                        .where(orders: { restaurant_id: @restaurant.id })
                        .where(created_at: start_date..end_date)
                        .where(payment_type: 'refund', status: 'completed')
    
    # Process OrderPayment refunds
    refunds.each do |refund|
      method = refund.payment_method || 'unknown'
      
      # Only adjust the amount if we have this payment method in our data
      if payment_data[method]
        # Subtract the refund amount from the total
        payment_data[method][:amount] -= refund.amount.to_f
        # Note: We don't subtract from count as the transaction still occurred
      end
    end
    
    # 4. Handle manual refunds from Order table (legacy refunds)
    manual_refunds = scope_query(Order)
                        .where(updated_at: start_date..end_date)
                        .where(payment_method: ['cash', 'other', 'clover', 'revel'])
                        .where.not(refund_amount: [nil, 0])
                        .where(status: 'refunded')
    
    # Process manual refunds
    manual_refunds.each do |order|
      # Skip if this refund already has an OrderPayment record
      next if OrderPayment.exists?(order_id: order.id, payment_type: 'refund')
      
      method = order.payment_method
      
      # Only adjust the amount if we have this payment method in our data
      if payment_data[method]
        # Subtract the refund amount from the total
        payment_data[method][:amount] -= order.refund_amount.to_f
      end
    end
    
    # Calculate totals
    total_amount = payment_data.values.sum { |p| p[:amount].to_f }
    total_count = payment_data.values.sum { |p| p[:count] }
    
    # Calculate percentages
    payment_data.each do |_, data|
      data[:percentage] = total_amount > 0 ? (data[:amount].to_f / total_amount.to_f * 100).round(2) : 0.0
    end
    
    {
      payment_methods: payment_data.values,
      total_amount: total_amount,
      total_count: total_count,
      detailed_orders: detailed_payment_orders # NEW: Include detailed order information
    }
  end

  # GET /admin/reports/vip_customers
  def vip_customers_report(start_date, end_date)
    # Get all VIP orders in date range
    vip_orders = scope_query(Order)
                    .where(created_at: start_date..end_date)
                    .where.not(vip_code: nil)
                    .where.not(status: 'canceled')
    
    # Group by user/contact info
    customer_data = {}
    
    vip_orders.each do |order|
      # Use user_id if available, otherwise use email as identifier
      customer_id = order.user_id || order.contact_email
      next unless customer_id # Skip if no identifier
      
      # Initialize customer data if not exists
      unless customer_data[customer_id]
        customer_data[customer_id] = {
          user_id: order.user_id,
          user_name: order.contact_name || (order.user&.full_name),
          email: order.contact_email || order.user&.email,
          total_spent: 0,
          order_count: 0,
          first_order_date: order.created_at,
          last_order_date: order.created_at,
          items: {}
        }
      end
      
      # Update customer data
      customer_record = customer_data[customer_id]
      customer_record[:total_spent] += order.total
      customer_record[:order_count] += 1
      customer_record[:first_order_date] = order.created_at if order.created_at < customer_record[:first_order_date]
      customer_record[:last_order_date] = order.created_at if order.created_at > customer_record[:last_order_date]
      
      # Track items
      order.items.each do |item|
        item_name = item['name']
        quantity = item['quantity'].to_i
        
        customer_record[:items][item_name] ||= 0
        customer_record[:items][item_name] += quantity
      end
    end
    
    # Format the data for response
    vip_customers = customer_data.values.map do |customer|
      {
        user_id: customer[:user_id],
        user_name: customer[:user_name] || 'Unknown',
        email: customer[:email] || 'Unknown',
        total_spent: customer[:total_spent],
        order_count: customer[:order_count],
        first_order_date: customer[:first_order_date],
        last_order_date: customer[:last_order_date],
        average_order_value: customer[:order_count] > 0 ? customer[:total_spent].to_f / customer[:order_count].to_f : 0.0,
        items: customer[:items].map { |name, quantity| { name: name, quantity: quantity } }
      }
    end
    
    # Calculate summary statistics
    total_customers = vip_customers.length
    total_orders = vip_customers.sum { |c| c[:order_count].to_i }
    total_revenue = vip_customers.sum { |c| c[:total_spent].to_f }
    
    summary = {
      total_vip_customers: total_customers,
      total_orders: total_orders,
      total_revenue: total_revenue.to_f,
      average_orders_per_vip: total_customers > 0 ? (total_orders.to_f / total_customers).round(2) : 0.0,
      average_spend_per_vip: total_customers > 0 ? (total_revenue.to_f / total_customers).round(2) : 0.0,
      repeat_customer_rate: total_customers > 0 ?
        (vip_customers.count { |c| c[:order_count].to_i > 1 }.to_f / total_customers).round(2) : 0.0
    }
    
    {
      vip_customers: vip_customers,
      summary: summary
    }
  end

  # GET /admin/reports/refunds
  def refunds_report(start_date, end_date)
    # Get all refunds from OrderPayment table
    refunds = OrderPayment.joins(:order)
                        .where(orders: { restaurant_id: @restaurant.id })
                        .where(created_at: start_date..end_date)
                        .where(payment_type: 'refund')
                        .includes(:order)
    
    # Group refunds by payment method
    refunds_by_method = {}
    total_refund_amount = 0
    refund_details = []
    
    refunds.each do |refund|
      method = refund.payment_method || 'unknown'
      amount = refund.amount.to_f
      
      # Update totals by payment method
      refunds_by_method[method] ||= {
        payment_method: method,
        count: 0,
        amount: 0.0
      }
      
      refunds_by_method[method][:count] += 1
      refunds_by_method[method][:amount] += amount
      total_refund_amount += amount
      
      # Collect detailed refund information
      order = refund.order
      refund_details << {
        id: refund.id,
        order_id: order.id,
        order_number: order.order_number,
        amount: amount,
        payment_method: method,
        status: refund.status,
        description: refund.description,
        created_at: refund.created_at,
        customer_name: order.contact_name,
        customer_email: order.contact_email,
        refunded_items: refund.get_refunded_items || [],
        original_order_total: order.total
      }
    end
    
    # Calculate percentages
    refunds_by_method.each do |_, data|
      data[:percentage] = total_refund_amount > 0 ? (data[:amount] / total_refund_amount * 100).round(2) : 0.0
    end
    
    # Get refund trends by day
    daily_refunds = refunds.group("DATE(order_payments.created_at)")
                          .sum(:amount)
    
    daily_trends = daily_refunds.map do |date, amount|
      {
        date: date.to_s,
        amount: amount.to_f.round(2)
      }
    end
    
    # Calculate summary statistics
    total_refunds_count = refunds.count
    average_refund_amount = total_refunds_count > 0 ? (total_refund_amount / total_refunds_count).round(2) : 0.0
    
    # Get orders in the same period for refund rate calculation
    total_orders = scope_query(Order)
                    .where(created_at: start_date..end_date)
                    .where.not(status: 'canceled')
                    .count
    
    total_revenue = scope_query(Order)
                     .where(created_at: start_date..end_date)
                     .where.not(status: 'canceled')
                     .sum(:total)
    
    refund_rate = total_orders > 0 ? (total_refunds_count.to_f / total_orders * 100).round(2) : 0.0
    refund_rate_by_amount = total_revenue > 0 ? (total_refund_amount / total_revenue * 100).round(2) : 0.0
    
    {
      summary: {
        total_refunds_count: total_refunds_count,
        total_refund_amount: total_refund_amount.round(2),
        average_refund_amount: average_refund_amount,
        refund_rate_by_orders: refund_rate,
        refund_rate_by_amount: refund_rate_by_amount,
        total_orders_in_period: total_orders,
        total_revenue_in_period: total_revenue.to_f.round(2)
      },
      refunds_by_method: refunds_by_method.values,
      daily_trends: daily_trends.sort_by { |d| d[:date] },
      refund_details: refund_details.sort_by { |r| r[:created_at] }.reverse
    }
  end
end
