# app/services/report_service.rb
class ReportService < TenantScopedService
  # GET /admin/reports/menu_items
  def menu_items_report(start_date, end_date)
    # Query to get all order items in date range
    orders = scope_query(Order)
              .where(created_at: start_date..end_date)
              .where.not(status: 'canceled')
    
    # Process orders to get item data
    item_data = {}
    category_data = {}
    
    # Create a cache of menu item IDs to their categories
    menu_item_categories = {}
    
    # Special case mapping for common items that might be missing from the database
    special_case_categories = {
      'Aloha Poke' => 'Bowls',
      'Ahi Burger' => 'Burgers',
      'Build-a-Bowl' => 'Bowls'
    }
    
    orders.each do |order|
      order.items.each do |item|
        item_id = item['id'].to_s
        item_name = item['name']
        quantity = item['quantity'].to_i
        price = item['price'].to_f
        customizations = item['customizations']
        
        # Look up the menu item's categories if not already cached
        if !menu_item_categories[item_id]
          # Try to find the menu item in the database
          menu_item = scope_query(MenuItem).includes(:categories).find_by(id: item_id.to_i)
          
          if menu_item
            # Get the categories for this menu item
            categories = menu_item.categories
            
            if categories.any?
              # Use the first category name, or join multiple categories
              menu_item_categories[item_id] = categories.map(&:name).join(', ')
              Rails.logger.info("Menu item #{item_id} (#{item_name}) has categories: #{categories.map(&:name).join(', ')}")
            else
              # Menu item exists but has no categories
              Rails.logger.info("Menu item #{item_id} (#{item_name}) exists but has no categories")
              
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
        customizations_key = customizations&.to_s || ""
        unique_item_key = "#{item_id}|#{customizations_key}"
        
        # Update item stats
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
        
        item_data[unique_item_key][:quantity_sold] += quantity
        item_data[unique_item_key][:revenue] += quantity * price
        
        # Update category stats
        if !category_data[category]
          category_data[category] = {
            name: category,
            quantity_sold: 0,
            revenue: 0
          }
        end
        
        category_data[category][:quantity_sold] += quantity
        category_data[category][:revenue] += quantity * price
      end
    end
    
    # Calculate average prices
    item_data.each do |_, item|
      item[:average_price] = item[:revenue] / item[:quantity_sold] if item[:quantity_sold] > 0
    end
    
    {
      items: item_data.values,
      categories: category_data.values
    }
  end

  # GET /admin/reports/payment_methods
  def payment_methods_report(start_date, end_date)
    # Initialize payment data hash
    payment_data = {}
    
    # 1. Get payments from OrderPayment table (excluding refunds)
    # Since OrderPayment doesn't have restaurant_id, we need to join with orders and filter by restaurant_id
    payments = OrderPayment.joins(:order)
                        .where(orders: { restaurant_id: @restaurant.id })
                        .where(created_at: start_date..end_date)
                        .where.not(payment_type: 'refund')
    
    # Process OrderPayment records
    payments.each do |payment|
      method = payment.payment_method || 'unknown'
      
      payment_data[method] ||= {
        payment_method: method,
        count: 0,
        amount: 0.0  # Ensure this is a float
      }
      
      payment_data[method][:count] += 1
      payment_data[method][:amount] += payment.amount.to_f  # Convert to float
    end
    
    # 2. Get manual payments directly from Order table
    # Find orders with manual payments that don't have corresponding OrderPayment records
    # Note: We exclude stripe_reader since it's already creating OrderPayment records
    manual_payment_orders = scope_query(Order)
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
    end
    
    # 3. Handle manual refunds from Order table
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
      total_count: total_count
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
end
