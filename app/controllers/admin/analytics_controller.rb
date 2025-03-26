# app/controllers/admin/analytics_controller.rb

module Admin
  class AnalyticsController < ApplicationController
    before_action :authorize_request
    before_action :require_admin!

    # Mark all actions as public endpoints that don't require restaurant context
    def public_endpoint?
      true
    end

    # GET /admin/analytics/customer_orders?start=YYYY-MM-DD&end=YYYY-MM-DD
    def customer_orders
      start_date = params[:start].present? ? Date.parse(params[:start]) : (Date.today - 30)
      end_date   = params[:end].present?   ? Date.parse(params[:end])   : Date.today
      end_date = end_date.end_of_day

      orders = Order
        .includes(:user)
        .where(created_at: start_date..end_date)
        .where.not(status: "cancelled")

      # Group them by user or by guest contact info
      grouped_orders = orders.group_by do |order|
        if order.user_id.present?
          "USER_#{order.user_id}"
        else
          name_str  = order.contact_name.to_s.strip.downcase
          phone_str = order.contact_phone.to_s.strip.downcase
          email_str = order.contact_email.to_s.strip.downcase
          "GUEST_#{name_str}_#{phone_str}_#{email_str}"
        end
      end

      report = grouped_orders.map do |_group_key, orders_in_group|
        total_spent = orders_in_group.sum(&:total)
        order_count = orders_in_group.size

        all_items = orders_in_group.flat_map(&:items)
        item_details = all_items.group_by { |i| i["name"] || "Unknown" }.map do |item_name, lines|
          {
            name: item_name,
            quantity: lines.sum { |ln| ln["quantity"] || 1 }
          }
        end

        first_order = orders_in_group.first
        if first_order.user_id.present?
          user_obj  = first_order.user
          user_name = user_obj&.full_name.presence || user_obj&.email || "Unknown User"
          user_id   = user_obj.id
        else
          fallback_name = first_order.contact_name.presence ||
                          first_order.contact_phone.presence ||
                          first_order.contact_email.presence ||
                          "Unknown Guest"
          user_name = "Guest (#{fallback_name})"
          user_id   = nil
        end

        {
          user_id: user_id,
          user_name: user_name,
          total_spent: total_spent.to_f.round(2),
          order_count: order_count,
          items: item_details
        }
      end

      render json: {
        start_date: start_date,
        end_date: end_date,
        results: report
      }
    end

    # GET /admin/analytics/revenue_trend?interval=day|week|month&start=...&end=...
    def revenue_trend
      interval   = params[:interval].presence || "day"
      start_date = params[:start].present? ? Date.parse(params[:start]) : 30.days.ago
      end_date   = params[:end].present?   ? Date.parse(params[:end])   : Date.today
      end_date = end_date.end_of_day

      orders = Order.where.not(status: "cancelled").where(created_at: start_date..end_date)

      results = case interval
      when "week"
        orders.group("extract(year from created_at), extract(week from created_at)")
              .select("extract(year from created_at) as yr, extract(week from created_at) as wk, SUM(total) as revenue")
              .order("yr, wk")
      when "month"
        orders.group("extract(year from created_at), extract(month from created_at)")
              .select("extract(year from created_at) as yr, extract(month from created_at) as mon, SUM(total) as revenue")
              .order("yr, mon")
      else # 'day'
        orders.group("DATE(created_at)")
              .select("DATE(created_at) as date, SUM(total) as revenue")
              .order("DATE(created_at)")
      end

      data = results.map do |row|
        if interval == "day"
          { label: row.date, revenue: row.revenue.to_f.round(2) }
        elsif interval == "week"
          { label: "Year #{row.yr.to_i} - Week #{row.wk.to_i}", revenue: row.revenue.to_f.round(2) }
        else
          { label: "Year #{row.yr.to_i}, Month #{row.mon.to_i}", revenue: row.revenue.to_f.round(2) }
        end
      end

      render json: {
        start_date: start_date,
        end_date: end_date,
        interval: interval,
        data: data
      }
    end

    # GET /admin/analytics/top_items?limit=5&start=...&end=...
    def top_items
      limit = (params[:limit] || 5).to_i
      start_date = params[:start].present? ? Date.parse(params[:start]) : 30.days.ago
      end_date   = params[:end].present?   ? Date.parse(params[:end])   : Date.today
      end_date = end_date.end_of_day

      orders = Order.where.not(status: "cancelled").where(created_at: start_date..end_date)
      all_items = orders.flat_map(&:items)

      grouped = all_items.group_by { |i| i["name"] || "Unknown" }
      results = grouped.map do |item_name, lines|
        qty = lines.sum { |ln| ln["quantity"] || 1 }
        rev = lines.sum { |ln| (ln["price"] || 0).to_f * (ln["quantity"] || 1) }
        { item_name: item_name, quantity_sold: qty, revenue: rev.round(2) }
      end

      top = results.sort_by { |r| -r[:revenue] }.first(limit)

      render json: {
        start_date: start_date,
        end_date: end_date,
        top_items: top
      }
    end

    # GET /admin/analytics/income_statement?year=2025
    def income_statement
      year = (params[:year] || Date.today.year).to_i
      year_start = Date.new(year, 1, 1).beginning_of_day
      year_end   = year_start.end_of_year

      orders = Order.where.not(status: "cancelled").where(created_at: year_start..year_end)
      monthly = orders.group("extract(month from created_at)")
                      .select("extract(month from created_at) as mon, SUM(total) as revenue")
                      .order("mon")

      # We'll map numeric months to names
      month_names = %w[January February March April May June July August September October November December]

      data = monthly.map do |row|
        m_index = row.mon.to_i - 1
        {
          month: month_names[m_index] || "Month #{row.mon.to_i}",
          revenue: row.revenue.to_f.round(2)
        }
      end

      render json: {
        year: year,
        income_statement: data
      }
    end

    # GET /admin/analytics/user_signups?start=YYYY-MM-DD&end=YYYY-MM-DD
    def user_signups
      start_date = params[:start].present? ? Date.parse(params[:start]) : (Date.today - 30)
      end_date   = params[:end].present?   ? Date.parse(params[:end])   : Date.today
      end_date = end_date.end_of_day

      # Query users created within the date range, grouped by day
      daily_signups = User
        .where(created_at: start_date..end_date)
        .group("DATE(created_at)")
        .select("DATE(created_at) as date, COUNT(*) as count")
        .order("date")

      # Format the data for the frontend
      data = daily_signups.map do |row|
        {
          date: row.date.to_s,
          count: row.count.to_i
        }
      end

      render json: {
        start_date: start_date,
        end_date: end_date,
        signups: data
      }
    end

    # GET /admin/analytics/user_activity_heatmap?start=YYYY-MM-DD&end=YYYY-MM-DD
    def user_activity_heatmap
      start_date = params[:start].present? ? Date.parse(params[:start]) : (Date.today - 30)
      end_date   = params[:end].present?   ? Date.parse(params[:end])   : Date.today
      end_date = end_date.end_of_day

      # Query orders within the date range, grouped by day of week (0-6, Sunday-Saturday) and hour (0-23)
      activity_data = Order
        .where(created_at: start_date..end_date)
        .where.not(status: "cancelled")
        .group("EXTRACT(DOW FROM created_at)")
        .group("EXTRACT(HOUR FROM created_at)")
        .count

      # Transform the data for the frontend
      # The keys in activity_data are arrays like [day, hour]
      heatmap_data = []

      # Initialize with zeros for all day/hour combinations
      (0..6).each do |day|
        (0..23).each do |hour|
          count = 0

          # Find the matching key in activity_data
          activity_data.each do |key, value|
            if key[0].to_i == day && key[1].to_i == hour
              count = value
              break
            end
          end

          heatmap_data << {
            day: day,
            hour: hour,
            value: count
          }
        end
      end

      # Day names for reference
      day_names = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]

      render json: {
        start_date: start_date,
        end_date: end_date,
        day_names: day_names,
        heatmap: heatmap_data
      }
    end

    private

    def require_admin!
      unless current_user && current_user.role.in?(%w[admin super_admin staff])
        render json: { error: "Forbidden" }, status: :forbidden
      end
    end
  end
end
