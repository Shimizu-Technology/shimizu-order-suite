# app/controllers/admin/analytics_controller.rb
module Admin
  class AnalyticsController < ApplicationController
    before_action :authorize_request
    before_action :require_admin!

    # GET /admin/analytics/customer_orders?start=YYYY-MM-DD&end=YYYY-MM-DD
    def customer_orders
      start_date = params[:start].present? ? Date.parse(params[:start]) : Date.today.beginning_of_month
      end_date   = params[:end].present?   ? Date.parse(params[:end])   : Date.today.end_of_month
      end_date = end_date.end_of_day

      orders = Order
        .includes(:user)
        .where(created_at: start_date..end_date)
        .where.not(status: 'cancelled')  # or adjust as needed

      # 1) Build a custom grouping key for each order:
      #    If there's a user_id => "USER_#{user_id}",
      #    else => "GUEST_#{contact_name + phone + email}" (a concatenated string).
      grouped_orders = orders.group_by do |order|
        if order.user_id.present?
          "USER_#{order.user_id}"
        else
          # Combine contact name/phone/email. Downcase/strip so “Leon” vs “leon” is recognized the same, if you like.
          name_str  = order.contact_name.to_s.strip.downcase
          phone_str = order.contact_phone.to_s.strip.downcase
          email_str = order.contact_email.to_s.strip.downcase

          "GUEST_#{name_str}_#{phone_str}_#{email_str}"
        end
      end

      # 2) For each group, sum totals and gather items
      report = grouped_orders.map do |group_key, orders_in_group|
        total_spent = orders_in_group.sum(&:total)
        order_count = orders_in_group.size

        # Flatten all items across these orders
        all_items = orders_in_group.flat_map(&:items)
        item_details = all_items.group_by { |i| i['name'] || 'Unknown' }.map do |item_name, lines|
          {
            name: item_name,
            quantity: lines.sum { |ln| ln['quantity'] || 1 }
          }
        end

        first_order = orders_in_group.first
        if first_order.user_id.present?
          # Real user
          user_obj   = first_order.user
          user_name  = user_obj&.full_name.presence || user_obj&.email || 'Unknown User'
          user_id    = user_obj.id
        else
          # Guest user => build a “Guest (info)”
          # or just “Guest: <contact_name>”
          fallback_name = first_order.contact_name.presence ||
                          first_order.contact_phone.presence ||
                          first_order.contact_email.presence ||
                          'Unknown Guest'

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

    private

    def require_admin!
      unless current_user && current_user.role.in?(%w[admin super_admin])
        render json: { error: 'Forbidden' }, status: :forbidden
      end
    end
  end
end
