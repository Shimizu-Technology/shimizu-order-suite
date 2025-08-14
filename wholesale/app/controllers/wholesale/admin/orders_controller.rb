# app/controllers/wholesale/admin/orders_controller.rb

module Wholesale
  module Admin
    class OrdersController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_fundraiser, only: [:index, :show, :update, :update_status, :update_tracking, :export, :export_all], if: :nested_route?
      before_action :set_order, only: [:show, :update, :update_status, :update_tracking, :export]
      before_action :set_restaurant_context
      
      # GET /wholesale/admin/orders
      # GET /wholesale/admin/fundraisers/:fundraiser_id/orders
      def index
        orders = current_restaurant.wholesale_orders.includes(:fundraiser, :participant, order_items: :item)
        
        # Apply fundraiser scoping if present
        if @fundraiser
          # Nested route: scope to specific fundraiser
          orders = orders.where(fundraiser_id: @fundraiser.id)
        elsif params[:fundraiser_id].present?
          # Parameter-based filtering for backward compatibility
          orders = orders.where(fundraiser_id: params[:fundraiser_id])
        end
        
        orders = orders.all
        
        # Add computed fields and format for frontend
        orders_with_details = orders.map do |order|
          # Derive payment status from order status
          payment_status = case order.status
          when 'pending' then 'pending'
          when 'paid', 'fulfilled', 'completed' then 'paid'
          when 'cancelled' then 'cancelled'
          else 'pending'
          end
          
          order.attributes.merge(
            'fundraiser_name' => order.fundraiser&.name,
            'participant_name' => order.participant&.name,
            'customer_name' => order.customer_name,
            'customer_email' => order.customer_email,
            'customer_phone' => order.customer_phone,
            'payment_status' => payment_status,
            'total' => order.total,
            'item_count' => order.order_items.sum(:quantity),
            'unique_item_count' => order.order_items.count,
            'items' => order.order_items.map do |order_item|
              {
                'id' => order_item.id,
                'name' => order_item.item&.name,
                'quantity' => order_item.quantity,
                'price_cents' => order_item.price_cents,
                'price' => order_item.price_cents / 100.0,
                'total_cents' => order_item.quantity * order_item.price_cents,
                'total' => (order_item.quantity * order_item.price_cents) / 100.0,
                'selected_options' => order_item.selected_options,
                'variant_description' => order_item.variant_description
              }
            end
          )
        end
        
        render_success(orders: orders_with_details)
      end
      
      # GET /wholesale/admin/orders/:id
      def show
        # Derive payment status from order status
        payment_status = case @order.status
        when 'pending' then 'pending'
        when 'paid', 'fulfilled', 'completed' then 'paid'
        when 'cancelled' then 'cancelled'
        else 'pending'
        end
        
        order_data = @order.attributes.merge(
          'fundraiser_name' => @order.fundraiser&.name,
          'participant_name' => @order.participant&.name,
          'customer_name' => @order.customer_name,
          'customer_email' => @order.customer_email,
          'customer_phone' => @order.customer_phone,
          'payment_status' => payment_status,
          'total' => @order.total,
          'item_count' => @order.order_items.sum(:quantity),
          'unique_item_count' => @order.order_items.count,
          'items' => @order.order_items.map do |order_item|
            {
              'id' => order_item.id,
              'name' => order_item.item&.name,
              'quantity' => order_item.quantity,
              'price_cents' => order_item.price_cents,
              'price' => order_item.price_cents / 100.0,
              'total_cents' => order_item.quantity * order_item.price_cents,
              'total' => (order_item.quantity * order_item.price_cents) / 100.0,
              'selected_options' => order_item.selected_options,
              'variant_description' => order_item.variant_description
            }
          end
        )
        
        render_success(order: order_data)
      end
      
      # PATCH/PUT /wholesale/admin/orders/:id
      def update
        if @order.update(order_params)
          render_success(order: @order, message: 'Order updated successfully!')
        else
          render_error('Failed to update order', errors: @order.errors.full_messages)
        end
      end
      
      # PATCH /wholesale/admin/orders/:id/update_status
      def update_status
        old_status = @order.status
        new_status = params[:status]
        
        if @order.update(status: new_status)
          # Send notifications for status changes
          send_status_change_notifications(@order, old_status, new_status)
          
          render_success(order: @order, message: "Order status updated to #{new_status} successfully!")
        else
          render_error('Failed to update order status', errors: @order.errors.full_messages)
        end
      end
      
      # PATCH /wholesale/admin/orders/:id/update_tracking
      def update_tracking
        if @order.update(tracking_number: params[:tracking_number])
          render_success(order: @order, message: 'Tracking number updated successfully!')
        else
          render_error('Failed to update tracking number', errors: @order.errors.full_messages)
        end
      end
      
      # GET /wholesale/admin/orders/:id/export
      def export
        # TODO: Implement individual order export
        render_success(message: 'Individual order export coming soon')
      end
      
      # PATCH /wholesale/admin/orders/bulk_update_status
      def bulk_update_status
        order_ids = params[:order_ids]
        new_status = params[:status]
        
        if order_ids.blank? || new_status.blank?
          render_error('Order IDs and status are required')
          return
        end
        
        orders = current_restaurant.wholesale_orders.where(id: order_ids)
        updated_count = 0
        failed_orders = []
        
        orders.each do |order|
          old_status = order.status
          
          if order.wholesale_can_transition_to?(new_status)
            if order.update(status: new_status)
              updated_count += 1
              # Send notifications for status changes
              send_status_change_notifications(order, old_status, new_status)
            else
              failed_orders << { id: order.id, errors: order.errors.full_messages }
            end
          else
            failed_orders << { id: order.id, errors: ["Cannot transition from #{old_status} to #{new_status}"] }
          end
        end
        
        message = "Updated #{updated_count} orders to #{new_status}"
        message += ". #{failed_orders.count} orders failed to update." if failed_orders.any?
        
        render_success(
          message: message,
          updated_count: updated_count,
          failed_orders: failed_orders
        )
      end
      
      # GET /wholesale/admin/orders/wholesale_statuses
      def wholesale_statuses
        render_success(statuses: Wholesale::Order.wholesale_statuses)
      end
      
      # GET /wholesale/admin/orders/export_all
      def export_all
        orders = current_restaurant.wholesale_orders.includes(:fundraiser, :participant, :items).all
        
        # Generate CSV data
        csv_data = generate_orders_csv(orders)
        
        respond_to do |format|
          format.csv do
            send_data csv_data, 
              filename: "wholesale-orders-#{Date.current.strftime('%Y%m%d')}.csv",
              type: 'text/csv',
              disposition: 'attachment'
          end
          format.json do
            # For AJAX requests, return download URL or data
            render_success(
              message: 'Export ready',
              csv_data: csv_data,
              filename: "wholesale-orders-#{Date.current.strftime('%Y%m%d')}.csv"
            )
          end
        end
      rescue => e
        render_error('Failed to export orders', errors: [e.message])
      end
      
      private
      
      def set_order
        query = current_restaurant.wholesale_orders
        
        # Additional scoping for nested routes
        if @fundraiser
          query = query.where(fundraiser_id: @fundraiser.id)
        end
        
        @order = query.find_by(id: params[:id])
        render_not_found('Order not found') unless @order
      end
      
      def order_params
        params.require(:order).permit(
          :status, :tracking_number, :notes
        )
      end
      
      def generate_orders_csv(orders)
        require 'csv'
        
        CSV.generate(headers: true) do |csv|
          csv << [
            'Order Number', 'Status', 'Customer Name', 'Customer Email',
            'Fundraiser', 'Participant', 'Total Amount', 'Created At',
            'Tracking Number', 'Items Count'
          ]
          
          orders.each do |order|
            csv << [
              order.order_number,
              order.status,
              order.customer_name,
              order.customer_email,
              order.fundraiser&.name,
              order.participant&.name || 'General Support',
              (order.total_cents / 100.0),
              order.created_at.strftime('%Y-%m-%d %H:%M'),
              order.tracking_number,
              order.order_items.sum(:quantity)
            ]
          end
        end
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
      
      def send_status_change_notifications(order, old_status, new_status)
        notification_channels = current_restaurant.admin_settings&.dig("notification_channels", "wholesale_orders") || {}
        restaurant_name = current_restaurant.name
        
        # Send notifications when order is fulfilled
        if old_status != 'fulfilled' && new_status == 'fulfilled'
          send_order_fulfilled_notifications(order, notification_channels, restaurant_name)
        end
        
        # Send notifications when order becomes ready for pickup
        if old_status != 'ready' && new_status == 'ready'
          send_order_ready_notifications(order, notification_channels, restaurant_name)
        end
        
        # Send notifications when order is completed
        if old_status != 'completed' && new_status == 'completed'
          send_order_completed_notifications(order, notification_channels, restaurant_name)
        end
        
        # Send notifications when order is shipped (if using shipping in future)
        if old_status != 'shipped' && new_status == 'shipped'
          send_order_shipped_notifications(order, notification_channels, restaurant_name)
        end
      end
      
      def send_order_fulfilled_notifications(order, notification_channels, restaurant_name)
        # Send email notification
        if notification_channels["email"] != false && order.customer_email.present?
          WholesaleOrderMailer.order_fulfilled(order).deliver_later
        end
        
        # Send SMS notification
        if notification_channels["sms"] == true && order.customer_phone.present?
          sms_sender = current_restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name
          participant_text = order.participant ? " supporting #{order.participant.name}" : ""
          
          # Only show location if we have a custom pickup location name, otherwise it's just the restaurant name
          pickup_location = order.fundraiser.pickup_location_name.present? ? " at #{order.fundraiser.pickup_display_name}" : ""
          
          # Only show pickup contact if it's different from the restaurant's main contact
          pickup_contact = ""
          if order.fundraiser.pickup_contact_phone.present? || order.fundraiser.contact_phone.present?
            contact_phone = order.fundraiser.pickup_contact_display_phone
            # Don't repeat the same phone number that's likely already known to the customer
            restaurant_phone = order.fundraiser.restaurant&.phone_number
            if contact_phone != restaurant_phone && contact_phone.present?
              pickup_contact = " Contact: #{contact_phone}."
            end
          end
          
          msg = "Hi #{order.customer_name}, your wholesale order ##{order.order_number} for #{order.fundraiser.name}#{participant_text} "\
                "is ready for pickup#{pickup_location}.#{pickup_contact} Thank you!"
          
          SendSmsJob.perform_later(to: order.customer_phone, body: msg, from: sms_sender)
        end
      end
      
      def send_order_ready_notifications(order, notification_channels, restaurant_name)
        # Send email notification
        if notification_channels["email"] != false && order.customer_email.present?
          WholesaleOrderMailer.order_ready(order).deliver_later
        end
        
        # Send SMS notification
        if notification_channels["sms"] == true && order.customer_phone.present?
          sms_sender = current_restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name
          participant_text = order.participant ? " supporting #{order.participant.name}" : ""
          
          pickup_location = order.fundraiser.pickup_display_name.present? ? " at #{order.fundraiser.pickup_display_name}" : ""
          pickup_contact = order.fundraiser.pickup_contact_display_phone.present? ? " Contact: #{order.fundraiser.pickup_contact_display_phone}" : ""
          
          msg = "Hi #{order.customer_name}, your wholesale order ##{order.order_number} for #{order.fundraiser.name}#{participant_text} "\
                "is now ready for pickup#{pickup_location}! Please bring your order confirmation.#{pickup_contact} Thank you!"
          
          SendSmsJob.perform_later(to: order.customer_phone, body: msg, from: sms_sender)
        end
      end
      
      def send_order_completed_notifications(order, notification_channels, restaurant_name)
        # Send email notification if needed in the future
        # For now, completed status doesn't trigger notifications since it's the final state
        
        # Could add SMS for completed status if needed:
        # if notification_channels["sms"] == true && order.customer_phone.present?
        #   sms_sender = current_restaurant.admin_settings&.dig("sms_sender_id").presence || restaurant_name
        #   participant_text = order.participant ? " supporting #{order.participant.name}" : ""
        #   
        #   msg = "Hi #{order.customer_name}, your wholesale order ##{order.order_number} for #{order.fundraiser.name}#{participant_text} "\
        #         "has been completed. Thank you for your support!"
        #   
        #   SendSmsJob.perform_later(to: order.customer_phone, body: msg, from: sms_sender)
        # end
      end
      
      def send_order_shipped_notifications(order, notification_channels, restaurant_name)
        # Future implementation for shipping notifications
        # Similar pattern to order_ready but for shipped status
      end
    end
  end
end