# app/controllers/wholesale/admin/analytics_controller.rb

module Wholesale
  module Admin
    class AnalyticsController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_fundraiser, only: [:fundraiser_analytics], if: :nested_route?
      before_action :set_date_range
      
      # GET /wholesale/admin/analytics
      def index
        # Support parameter-based fundraiser filtering for backward compatibility
        fundraiser_id = params[:fundraiser_id]
        analytics_data = generate_analytics_data(fundraiser_id: fundraiser_id)
        render_success(analytics_data)
      end
      
      # GET /wholesale/admin/fundraisers/:fundraiser_id/analytics
      def fundraiser_analytics
        analytics_data = generate_analytics_data(fundraiser_id: @fundraiser.id)
        render_success(analytics_data)
      end
      
      # GET /wholesale/admin/analytics/revenue
      def revenue
        revenue_data = generate_revenue_analytics
        render_success(revenue_data)
      end
      
      # GET /wholesale/admin/analytics/participants
      def participants
        participant_data = generate_participant_analytics
        render_success(participant_data)
      end
      
      # GET /wholesale/admin/analytics/fundraisers
      def fundraisers
        fundraiser_data = generate_fundraiser_analytics
        render_success(fundraiser_data)
      end
      
      # GET /wholesale/admin/analytics/export
      def export
        analytics_data = generate_analytics_data
        csv_data = generate_analytics_csv(analytics_data)
        
        respond_to do |format|
          format.csv do
            send_data csv_data,
              filename: "wholesale-analytics-#{@period}-#{Date.current.strftime('%Y%m%d')}.csv",
              type: 'text/csv',
              disposition: 'attachment'
          end
          format.json do
            render_success(
              message: 'Export ready',
              csv_data: csv_data,
              filename: "wholesale-analytics-#{@period}-#{Date.current.strftime('%Y%m%d')}.csv"
            )
          end
        end
      rescue => e
        render_error('Failed to export analytics', errors: [e.message])
      end
      
      private
      
      def generate_analytics_data(fundraiser_id: nil)
        # Get base data - scope to fundraiser if provided
        fundraisers = current_restaurant.wholesale_fundraisers
        orders = current_restaurant.wholesale_orders.where(created_at: @date_range)
        participants = Wholesale::Participant.joins(:fundraiser).where(wholesale_fundraisers: { restaurant_id: current_restaurant.id })
        
        if fundraiser_id.present?
          fundraisers = fundraisers.where(id: fundraiser_id)
          orders = orders.where(fundraiser_id: fundraiser_id)
          participants = participants.where(fundraiser_id: fundraiser_id)
        end
        
        fundraisers = fundraisers.all
        
        # Calculate totals
        total_revenue = orders.sum(:total_cents) / 100.0
        total_orders = orders.count
        active_fundraisers = fundraisers.where(active: true).count
        total_participants = participants.count
        pending_orders = orders.where(status: 'pending').count
        
        # Calculate averages
        average_order_value = total_orders > 0 ? total_revenue / total_orders : 0
        
        # Calculate growth (placeholder - would need historical data)
        revenue_growth = 0
        orders_growth = 0
        
        {
          totalRevenue: total_revenue,
          revenueGrowth: revenue_growth,
          totalOrders: total_orders,
          ordersGrowth: orders_growth,
          activeFundraisers: active_fundraisers,
          totalFundraisers: fundraisers.count,
          totalParticipants: total_participants,
          pendingOrders: pending_orders,
          averageOrderValue: average_order_value,
          conversionRate: 0, # Would need visitor data
          topFundraisers: generate_top_fundraisers(fundraisers, orders),
          topParticipants: generate_enhanced_participant_analytics(participants, orders),
          generalSupport: generate_general_support_analytics(orders),
          topItems: generate_enhanced_item_analytics(orders),
          itemVariantBreakdown: generate_item_variant_breakdown(orders),
          revenueByMonth: generate_revenue_by_month(orders),
          ordersByStatus: generate_orders_by_status(orders),
          variantAnalytics: generate_variant_analytics(orders),
          dailyTrends: generate_daily_trends(orders)
        }
      end
      
      def generate_top_fundraisers(fundraisers, orders)
        fundraisers.map do |fundraiser|
          fundraiser_orders = orders.where(fundraiser: fundraiser)
          {
            id: fundraiser.id,
            name: fundraiser.name,
            revenue: fundraiser_orders.sum(:total_cents) / 100.0,
            orders: fundraiser_orders.count,
            participants: fundraiser.participants.count
          }
        end.sort_by { |f| -f[:revenue] }.first(5)
      end
      
      def generate_top_participants(participants, orders)
        participants.map do |participant|
          participant_orders = orders.where(participant: participant)
          goal_amount = participant.goal_amount_cents ? (participant.goal_amount_cents / 100.0) : 0
          raised = participant_orders.sum(:total_cents) / 100.0
          
          {
            id: participant.id,
            name: participant.name,
            fundraiser: participant.fundraiser&.name || 'Unknown',
            raised: raised,
            goal: goal_amount,
            progress: goal_amount > 0 ? (raised / goal_amount * 100).round(1) : 0
          }
        end.sort_by { |p| -p[:raised] }.first(5)
      end
      
      def generate_general_support_analytics(orders)
        # Get orders that don't have a specific participant (general support)
        general_orders = orders.where(participant_id: nil)
        
        {
          orders_count: general_orders.count,
          total_revenue: general_orders.sum(:total_cents) / 100.0,
          percentage_of_total: orders.count > 0 ? (general_orders.count.to_f / orders.count * 100).round(1) : 0
        }
      end
      
      def generate_top_items(orders)
        # Get all order items from these orders
        order_items = Wholesale::OrderItem.joins(:order)
                                          .where(wholesale_orders: { id: orders.pluck(:id) })
                                          .includes(:item)
        
        item_stats = {}
        order_items.each do |item|
          item_name = item.item&.name || "Item ##{item.item_id}"
          item_stats[item_name] ||= { quantity: 0, revenue: 0 }
          item_stats[item_name][:quantity] += item.quantity
          item_stats[item_name][:revenue] += item.quantity * item.price_cents
        end
        
        item_stats.map do |name, stats|
          {
            id: name.hash, # Use name hash as ID
            name: name,
            quantity: stats[:quantity],
            revenue: stats[:revenue] / 100.0
          }
        end.sort_by { |i| -i[:revenue] }.first(5)
      end
      
      def generate_variant_analytics(orders)
        # Analyze size and color popularity across all order items
        size_stats = Hash.new { |h, k| h[k] = { quantity: 0, revenue: 0.0, orders: 0 } }
        color_stats = Hash.new { |h, k| h[k] = { quantity: 0, revenue: 0.0, orders: 0 } }
        combination_stats = Hash.new { |h, k| h[k] = { quantity: 0, revenue: 0.0, orders: 0 } }
        
        order_items = Wholesale::OrderItem.joins(:order)
                                          .where(wholesale_orders: { id: orders.pluck(:id) })
        
        order_items.each do |order_item|
          next unless order_item.selected_options.present?
          
          selected_size = order_item.selected_options['size']
          selected_color = order_item.selected_options['color']
          quantity = order_item.quantity
          revenue = order_item.quantity * order_item.price_cents / 100.0
          
          # Track size popularity
          if selected_size.present?
            size_stats[selected_size][:quantity] += quantity
            size_stats[selected_size][:revenue] += revenue
            size_stats[selected_size][:orders] += 1
          end
          
          # Track color popularity  
          if selected_color.present?
            color_stats[selected_color][:quantity] += quantity
            color_stats[selected_color][:revenue] += revenue
            color_stats[selected_color][:orders] += 1
          end
          
          # Track size+color combinations
          if selected_size.present? && selected_color.present?
            combo_key = "#{selected_size}/#{selected_color}"
            combination_stats[combo_key][:quantity] += quantity
            combination_stats[combo_key][:revenue] += revenue
            combination_stats[combo_key][:orders] += 1
          end
        end
        
        {
          sizes: size_stats.map do |size, stats|
            {
              name: size,
              quantity_sold: stats[:quantity],
              revenue: stats[:revenue],
              orders_count: stats[:orders]
            }
          end.sort_by { |s| -s[:quantity_sold] }.first(10),
          
          colors: color_stats.map do |color, stats|
            {
              name: color,
              quantity_sold: stats[:quantity],
              revenue: stats[:revenue],
              orders_count: stats[:orders]
            }
          end.sort_by { |c| -c[:quantity_sold] }.first(10),
          
          combinations: combination_stats.map do |combo, stats|
            size, color = combo.split('/')
            {
              size: size,
              color: color,
              combination: combo,
              quantity_sold: stats[:quantity],
              revenue: stats[:revenue],
              orders_count: stats[:orders]
            }
          end.sort_by { |c| -c[:quantity_sold] }.first(15)
        }
      end
      
      def generate_revenue_by_month(orders)
        # Group orders by month and calculate revenue
        monthly_data = orders.group_by { |order| order.created_at.strftime('%b') }
        
        ['Oct', 'Nov', 'Dec', 'Jan'].map do |month|
          month_orders = monthly_data[month] || []
          wholesale_revenue = month_orders.sum(&:total_cents) / 100.0
          
          {
            month: month,
            wholesale: wholesale_revenue,
            retail: 0 # Would need to query retail orders
          }
        end
      end
      
      def generate_orders_by_status(orders)
        status_counts = orders.group(:status).count
        total = orders.count
        
        status_counts.map do |status, count|
          {
            status: status.humanize,
            count: count,
            percentage: total > 0 ? (count.to_f / total * 100).round(1) : 0
          }
        end
      end
      
      def generate_revenue_analytics
        # Additional revenue-focused analytics
        {
          message: 'Revenue analytics endpoint coming soon'
        }
      end
      
      def generate_participant_analytics
        # Additional participant-focused analytics
        {
          message: 'Participant analytics endpoint coming soon'
        }
      end
      
      def generate_fundraiser_analytics
        # Additional fundraiser-focused analytics
        {
          message: 'Fundraiser analytics endpoint coming soon'
        }
      end
      
      def generate_analytics_csv(data)
        require 'csv'
        
        CSV.generate(headers: true) do |csv|
          csv << ['Metric', 'Value']
          csv << ['Total Revenue', "$#{data[:totalRevenue]}"]
          csv << ['Total Orders', data[:totalOrders]]
          csv << ['Active Fundraisers', data[:activeFundraisers]]
          csv << ['Total Participants', data[:totalParticipants]]
          csv << ['Average Order Value', "$#{data[:averageOrderValue]}"]
          csv << ['Pending Orders', data[:pendingOrders]]
          
          csv << []
          csv << ['Top Fundraisers', '']
          data[:topFundraisers].each do |fundraiser|
            csv << [fundraiser[:name], "$#{fundraiser[:revenue]}"]
          end
          
          csv << []
          csv << ['Top Participants', '']
          data[:topParticipants].each do |participant|
            csv << [participant[:name], "$#{participant[:raised]}"]
          end
        end
      end
      
      def set_date_range
        @period = params[:period] || '30d'
        
        case @period
        when '7d'
          @date_range = 7.days.ago..Time.current
        when '30d'
          @date_range = 30.days.ago..Time.current
        when '90d'
          @date_range = 90.days.ago..Time.current
        when '1y'
          @date_range = 1.year.ago..Time.current
        else
          @date_range = 30.days.ago..Time.current
        end
      end
      
      def generate_enhanced_participant_analytics(participants, orders)
        participants.map do |participant|
          participant_orders = orders.where(participant: participant)
          goal_amount = participant.goal_amount_cents ? (participant.goal_amount_cents / 100.0) : 0
          raised = participant_orders.sum(:total_cents) / 100.0
          avg_order_value = participant_orders.count > 0 ? raised / participant_orders.count : 0
          
          {
            id: participant.id,
            name: participant.name,
            fundraiser: participant.fundraiser&.name || 'Unknown',
            raised: raised,
            goal: goal_amount,
            progress: goal_amount > 0 ? (raised / goal_amount * 100).round(1) : 0,
            orders_count: participant_orders.count,
            average_order_value: avg_order_value.round(2),
            goal_percentage: goal_amount > 0 ? (raised / goal_amount * 100).round(1) : nil
          }
        end.sort_by { |p| -p[:raised] }
      end
      
      def generate_enhanced_item_analytics(orders)
        # Get all order items from these orders
        order_items = Wholesale::OrderItem.joins(:order)
                                          .where(wholesale_orders: { id: orders.pluck(:id) })
                                          .includes(:item)
        
        item_stats = {}
        order_items.each do |order_item|
          item = order_item.item
          next unless item
          
          item_stats[item.id] ||= { 
            id: item.id,
            name: item.name, 
            quantity: 0, 
            revenue: 0,
            orders_count: 0,
            unique_orders: Set.new,
            variants: {}
          }
          
          item_stats[item.id][:quantity] += order_item.quantity
          item_stats[item.id][:revenue] += order_item.quantity * order_item.price_cents
          item_stats[item.id][:unique_orders].add(order_item.order_id)
          
          # Track variants for this item
          if order_item.selected_options.present?
            variant_key = order_item.selected_options.sort.to_h.to_s
            item_stats[item.id][:variants][variant_key] ||= {
              options: order_item.selected_options,
              quantity: 0,
              revenue: 0
            }
            item_stats[item.id][:variants][variant_key][:quantity] += order_item.quantity
            item_stats[item.id][:variants][variant_key][:revenue] += order_item.quantity * order_item.price_cents
          end
        end
        
        item_stats.map do |item_id, stats|
          {
            id: item_id,
            name: stats[:name],
            quantity: stats[:quantity],
            revenue: stats[:revenue] / 100.0,
            orders_count: stats[:unique_orders].size,
            average_quantity_per_order: stats[:unique_orders].size > 0 ? (stats[:quantity].to_f / stats[:unique_orders].size).round(2) : 0,
            variant_count: stats[:variants].size,
            top_variants: stats[:variants].map do |variant_key, variant_data|
              {
                options: variant_data[:options],
                quantity: variant_data[:quantity],
                revenue: variant_data[:revenue] / 100.0,
                percentage_of_item: stats[:quantity] > 0 ? (variant_data[:quantity].to_f / stats[:quantity] * 100).round(1) : 0
              }
            end.sort_by { |v| -v[:quantity] }.first(3)
          }
        end.sort_by { |i| -i[:revenue] }
      end
      
      def generate_item_variant_breakdown(orders)
        # Detailed breakdown of variants by item
        order_items = Wholesale::OrderItem.joins(:order)
                                          .where(wholesale_orders: { id: orders.pluck(:id) })
                                          .includes(:item)
        
        item_variants = {}
        order_items.each do |order_item|
          item = order_item.item
          next unless item && order_item.selected_options.present?
          
          item_variants[item.name] ||= {}
          
          size = order_item.selected_options['size']
          color = order_item.selected_options['color']
          
          if size.present?
            item_variants[item.name][size] ||= { quantity: 0, revenue: 0, colors: {} }
            item_variants[item.name][size][:quantity] += order_item.quantity
            item_variants[item.name][size][:revenue] += order_item.quantity * order_item.price_cents
            
            if color.present?
              item_variants[item.name][size][:colors][color] ||= { quantity: 0, revenue: 0 }
              item_variants[item.name][size][:colors][color][:quantity] += order_item.quantity
              item_variants[item.name][size][:colors][color][:revenue] += order_item.quantity * order_item.price_cents
            end
          end
        end
        
        item_variants.map do |item_name, sizes|
          {
            item_name: item_name,
            sizes: sizes.map do |size, size_data|
              {
                size: size,
                quantity: size_data[:quantity],
                revenue: size_data[:revenue] / 100.0,
                colors: size_data[:colors].map do |color, color_data|
                  {
                    color: color,
                    quantity: color_data[:quantity],
                    revenue: color_data[:revenue] / 100.0
                  }
                end.sort_by { |c| -c[:quantity] }
              }
            end.sort_by { |s| -s[:quantity] }
          }
        end.sort_by { |item| -item[:sizes].sum { |s| s[:quantity] } }
      end
      
      def generate_daily_trends(orders)
        # Group orders by day for trend analysis
        daily_data = orders.group("DATE(created_at)").group(:status).count
        daily_revenue = orders.group("DATE(created_at)").sum(:total_cents)
        
        trend_data = {}
        daily_data.each do |(date, status), count|
          trend_data[date] ||= { date: date, orders: 0, revenue: 0, statuses: {} }
          trend_data[date][:orders] += count
          trend_data[date][:statuses][status] = count
        end
        
        daily_revenue.each do |date, revenue_cents|
          trend_data[date] ||= { date: date, orders: 0, revenue: 0, statuses: {} }
          trend_data[date][:revenue] = revenue_cents / 100.0
        end
        
        trend_data.values.sort_by { |d| d[:date] }.last(30) # Last 30 days
      end

      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end

      def set_fundraiser
        @fundraiser = Wholesale::Fundraiser.where(restaurant: current_restaurant)
          .find_by(id: params[:fundraiser_id])
        render_not_found('Fundraiser not found') unless @fundraiser
      end

      def nested_route?
        params[:fundraiser_id].present?
      end
    end
  end
end