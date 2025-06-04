# app/controllers/api/wholesale/fundraiser_orders_controller.rb

module Api
  module Wholesale
    class FundraiserOrdersController < Api::Wholesale::ApiController
      include TenantIsolation
      
      before_action :authorize_request, except: [:create, :show]
      before_action :optional_authorize, only: [:create, :show]
      before_action :ensure_tenant_context

      # GET /api/fundraiser_orders
      def index
        # Use Pundit's policy_scope to filter orders based on user role and ensure tenant isolation
        @orders = policy_scope(Order).fundraiser_orders

        # Filter by fundraiser_id if provided
        if params[:fundraiser_id].present?
          @orders = @orders.by_fundraiser(params[:fundraiser_id])
        end

        # Filter by participant_id if provided
        if params[:participant_id].present?
          @orders = @orders.by_participant(params[:participant_id])
        end

        # Filter by status if provided
        if params[:status].present?
          @orders = @orders.where(status: params[:status])
        end

        # Filter by date range if provided
        if params[:date_from].present? && params[:date_to].present?
          date_from = Time.zone.parse(params[:date_from]).beginning_of_day
          date_to = Time.zone.parse(params[:date_to]).end_of_day
          @orders = @orders.where(created_at: date_from..date_to)
        end

        # Search functionality
        if params[:search].present?
          search_term = "%#{params[:search]}%"
          @orders = @orders.where(
            "id::text ILIKE ? OR contact_name ILIKE ? OR contact_email ILIKE ? OR contact_phone ILIKE ? OR special_instructions ILIKE ?",
            search_term, search_term, search_term, search_term, search_term
          )
        end

        # Get total count after filtering but before pagination
        total_count = @orders.count

        # Add pagination
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 10).to_i

        # Apply sorting
        sort_by = params[:sort_by] || 'created_at'
        sort_direction = params[:sort_direction] || 'desc'
        
        # Validate sort parameters to prevent SQL injection
        valid_sort_columns = ['id', 'created_at', 'updated_at', 'status', 'total']
        valid_sort_directions = ['asc', 'desc']
        
        sort_by = 'created_at' unless valid_sort_columns.include?(sort_by)
        sort_direction = 'desc' unless valid_sort_directions.include?(sort_direction)
        
        # Include associations to ensure data is available in the response
        @orders = @orders.includes(:fundraiser, :fundraiser_participant)
                         .order("#{sort_by} #{sort_direction}")
                         .offset((page - 1) * per_page)
                         .limit(per_page)

        # Calculate total pages
        total_pages = (total_count.to_f / per_page).ceil

        # Include fundraiser and participant data in the response
        orders_with_associations = @orders.as_json(include: [:fundraiser, :fundraiser_participant])

        render json: {
          orders: orders_with_associations,
          total_count: total_count,
          page: page,
          per_page: per_page,
          total_pages: total_pages
        }, status: :ok
      end

      # GET /api/fundraiser_orders/:id
      def show
        order = Order.find(params[:id])
        authorize order
        render json: order.as_json(include: [:fundraiser, :fundraiser_participant])
      end

      # Constants for order types
      # Constants for fundraiser order subtypes
      GENERAL_SUPPORT_TYPE = "general_support"
      PARTICIPANT_SUPPORT_TYPE = "participant_support"
      
      # POST /api/fundraiser_orders
      def create
        # Optional decode of JWT for user lookup, treat as guest if invalid
        if request.headers["Authorization"].present?
          token = request.headers["Authorization"].split(" ").last
          begin
            decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: "HS256")[0]
            user_id = decoded["user_id"]
            found_user = User.find_by(id: user_id)
            @current_user = found_user if found_user
          rescue JWT::DecodeError
            # do nothing => treat as guest
          end
        end

        # Try primary nested params first, then fall back to legacy flat params for backward compatibility
        begin
          # Determine which parameter structure to use
          # This allows for a gradual transition to the new structure
          order_params = if params[:fundraiser_order].present?
            fundraiser_order_params
          else
            legacy_fundraiser_order_params
          end
          
          # If we don't have valid params from either method, return an error
          if order_params.empty?
            return render json: { error: "Missing required parameters" }, status: :unprocessable_entity
          end
          
          # Verify fundraiser exists and is active with proper tenant isolation
          fundraiser = Fundraiser.find_by(id: order_params[:fundraiser_id])
          
          if fundraiser.nil?
            return render json: { error: "Fundraiser not found" }, status: :unprocessable_entity
          end
          
          # Ensure the fundraiser belongs to the current tenant context
          authorize fundraiser, :show?
          
          unless fundraiser.active?
            return render json: { error: "This fundraiser is no longer active" }, status: :unprocessable_entity
          end
        rescue Pundit::NotAuthorizedError
          return render json: { error: "You don't have permission to access this fundraiser" }, status: :forbidden
        end

        # Verify participant exists and belongs to the fundraiser with proper tenant isolation
        if order_params[:items].present? && order_params[:items].any?
          participant_ids = order_params[:items].map { |item| item[:participant_id] }.compact.uniq
          
          # Verify all participants exist and belong to the fundraiser using policy_scope for tenant isolation
          participants = policy_scope(FundraiserParticipant).where(id: participant_ids, fundraiser_id: fundraiser.id)
          
          if participants.count != participant_ids.count
            return render json: { error: "One or more participants not found or do not belong to this fundraiser" }, status: :unprocessable_entity
          end
          
          # Additional authorization check for each participant
          begin
            participants.each { |participant| authorize participant, :show? }
          rescue Pundit::NotAuthorizedError
            return render json: { error: "You don't have permission to access one or more participants" }, status: :forbidden
          end
        end

        # Initialize order parameters
        new_params = {
          restaurant_id: fundraiser.restaurant_id,
          user_id: @current_user&.id,
          created_by_user_id: @current_user&.id,
          is_fundraiser_order: true,
          fundraiser_id: fundraiser.id,
          items: order_params[:items],
          total: order_params[:total],
          contact_name: order_params[:contact_name],
          contact_email: order_params[:contact_email],
          contact_phone: order_params[:contact_phone],
          # shipping_address field removed as it's not used and causes unknown attribute error
          special_instructions: order_params[:special_instructions],
          transaction_id: order_params[:transaction_id],
          payment_method: order_params[:payment_method],
          payment_details: order_params[:payment_details],
          fulfillment_method: order_params[:fulfillment_method] || 'pickup',
          status: "pending",
          payment_status: "completed",
          payment_amount: order_params[:total],
        }
        
        # Set pickup_location_id if fulfillment method is pickup
        if new_params[:fulfillment_method] == 'pickup'
          # Use provided pickup location or fall back to default location
          if order_params[:pickup_location_id].present?
            new_params[:pickup_location_id] = order_params[:pickup_location_id]
          else
            # Find the default location for the restaurant
            restaurant = Restaurant.find(fundraiser.restaurant_id)
            default_location = restaurant.locations.find_by(is_default: true) || restaurant.locations.first
            
            if default_location
              new_params[:pickup_location_id] = default_location.id
            else
              return render json: { error: "No pickup location available for this restaurant" }, status: :unprocessable_entity
            end
          end
        end

        # Determine fundraiser order subtype and handle participant assignment
        # If all items have null participant_ids, this is a general support order
        # Otherwise, it's a participant support order
        is_general_support = participant_ids.compact.empty?
        
        # All fundraiser orders have order_type='fundraiser' in the database
        # The subtype (general_support or participant_support) is handled by the virtual attribute
        if is_general_support
          # For general support orders, we'll set a special attribute to bypass the validation
          new_params[:fundraiser_order_subtype] = GENERAL_SUPPORT_TYPE
        elsif participant_ids.present? && participant_ids.first.present?
          # For participant support orders, set the first participant ID
          new_params[:fundraiser_participant_id] = participant_ids.first
          new_params[:fundraiser_order_subtype] = PARTICIPANT_SUPPORT_TYPE
        end
        
        # Create the order using OrderService for proper tenant isolation
        begin
          order_service = OrderService.new(fundraiser.restaurant)
          @order = order_service.create_order(new_params)
        rescue ArgumentError => e
          # Handle tenant isolation errors
          Rails.logger.error("Tenant isolation error: #{e.message}")
          return render json: { error: "Unable to create order: #{e.message}" }, status: :forbidden
        rescue => e
          # Handle other errors
          Rails.logger.error("Order creation error: #{e.message}")
          return render json: { error: "Unable to create order: #{e.message}" }, status: :unprocessable_entity
        end

        if @order.save
          # Broadcast the new order via WebSockets
          WebsocketBroadcastService.broadcast_new_order(@order)
          
          # Create an OrderPayment record for the initial payment
          if @order.payment_method.present? && @order.payment_amount.present? && @order.payment_amount.to_f > 0
            payment_id = @order.payment_id || @order.transaction_id || "FUNDRAISER-#{SecureRandom.hex(8)}"
            
            payment = @order.order_payments.create(
              payment_type: "initial",
              amount: @order.payment_amount,
              payment_method: @order.payment_method,
              status: "paid",
              transaction_id: @order.transaction_id || payment_id,
              payment_id: payment_id,
              description: "Initial payment for fundraiser order"
            )
          end

          # Send notifications if configured
          notification_channels = @order.restaurant.admin_settings&.dig("notification_channels", "orders") || {}
      
          # Send email notification to admin
          if notification_channels["email"] != false
            OrderMailer.order_confirmation(@order).deliver_later
          end
          
          # Send wholesale order confirmation email to customer
          if @order.contact_email.present?
            OrderMailer.wholesale_order_confirmation(@order).deliver_later
          end
          
          # Note: Admin notifications are handled by callbacks in the Order model via
          # notify_pushover and notify_whatsapp, so we don't need to send SMS to admins here
          
          # Send SMS confirmation to customer if phone provided
          if notification_channels["sms"] == true && @order.contact_phone.present?
            sms_sender = @order.restaurant.admin_settings&.dig("sms_sender_id").presence || @order.restaurant.name
            
            # Format item list for SMS
            item_list = @order.items.map { |i| "#{i['quantity']}x #{i['name']}" }.join(", ")
            
            # Create customer SMS message
            customer_message = <<~TXT.squish
              Hi #{@order.contact_name.presence || 'Customer'},
              thanks for your fundraiser order from #{@order.restaurant.name}!
              Order ##{@order.order_number.presence || @order.id}: #{item_list},
              total: $#{sprintf("%.2f", @order.total.to_f)}.
              We'll contact you when your order is ready!
            TXT
            
            # Send SMS asynchronously
            SendSmsJob.perform_later(to: @order.contact_phone, body: customer_message, from: sms_sender)
          end

          render json: @order, status: :created
        else
          render json: { error: @order.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # GET /api/fundraiser_orders/by_fundraiser/:fundraiser_id
      def by_fundraiser
        fundraiser = Fundraiser.find(params[:fundraiser_id])
        authorize fundraiser, :show?
        @orders = policy_scope(Order).fundraiser_orders.by_fundraiser(fundraiser.id)
        
        # Apply pagination
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 10).to_i
        
        total_count = @orders.count
        total_pages = (total_count.to_f / per_page).ceil
        
        @orders = @orders.includes(:fundraiser_participant)
                        .order(created_at: :desc)
                        .offset((page - 1) * per_page)
                        .limit(per_page)
        
        render json: {
          orders: @orders.as_json(include: :fundraiser_participant),
          total_count: total_count,
          page: page,
          per_page: per_page,
          total_pages: total_pages
        }, status: :ok
      end

      # GET /api/fundraiser_orders/by_participant/:participant_id
      def by_participant
        participant = FundraiserParticipant.find(params[:participant_id])
        authorize participant, :show?
        @orders = policy_scope(Order).fundraiser_orders.by_participant(participant.id)
        
        # Apply pagination
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 10).to_i
        
        total_count = @orders.count
        total_pages = (total_count.to_f / per_page).ceil
        
        @orders = @orders.includes(:fundraiser)
                        .order(created_at: :desc)
                        .offset((page - 1) * per_page)
                        .limit(per_page)
        
        render json: {
          orders: @orders.as_json(include: :fundraiser),
          total_count: total_count,
          page: page,
          per_page: per_page,
          total_pages: total_pages
        }, status: :ok
      end

      # GET /api/fundraiser_orders/stats
      def stats
        # Get basic stats for all fundraiser orders with proper tenant isolation
        total_orders = policy_scope(Order).fundraiser_orders.count
        total_revenue = policy_scope(Order).fundraiser_orders.sum(:total)
        
        # Get stats by fundraiser with proper tenant isolation
        fundraiser_stats = policy_scope(Fundraiser).joins(:orders)
                                    .select('fundraisers.id, fundraisers.name, COUNT(orders.id) as order_count, SUM(orders.total) as total_revenue')
                                    .where(orders: { is_fundraiser_order: true })
                                    .group('fundraisers.id, fundraisers.name')
                                    .order('total_revenue DESC')
        
        # Get stats by participant - ensure tenant isolation
        participant_stats = policy_scope(FundraiserParticipant).joins(:orders)
                                               .select('fundraiser_participants.id, fundraiser_participants.name, fundraiser_participants.fundraiser_id, COUNT(orders.id) as order_count, SUM(orders.total) as total_revenue')
                                               .group('fundraiser_participants.id, fundraiser_participants.name, fundraiser_participants.fundraiser_id')
                                               .order('total_revenue DESC')
        
        render json: {
          total_orders: total_orders,
          total_revenue: total_revenue,
          fundraiser_stats: fundraiser_stats,
          participant_stats: participant_stats
        }, status: :ok
      end

      private

      def fundraiser_order_params
        # Now that frontend consistently wraps data in fundraiser_order key,
        # we can simplify this to match the standard controller pattern
        params.require(:fundraiser_order).permit(
          :fundraiser_id,
          :total,
          :contact_name,
          :contact_email,
          :contact_phone,
          :special_instructions,
          :transaction_id,
          :payment_method,
          :fulfillment_method,
          :pickup_location_id,
          :order_type,
          payment_details: {},
          items: [:id, :quantity, :price, :name, :participant_id]
        )
      end
      
      # Fallback method for handling flat parameters structure
      # This provides backward compatibility if needed
      def legacy_fundraiser_order_params
        # Only use this if fundraiser_order is not present but other params are
        if !params[:fundraiser_order].present? && (params[:fundraiser_id].present? || params[:items].present? || params[:contact_name].present?)
          params.permit(
            :fundraiser_id,
            :total,
            :contact_name,
            :contact_email,
            :contact_phone,
            :special_instructions,
            :transaction_id,
            :payment_method,
            :fulfillment_method,
            :pickup_location_id,
            payment_details: {},
            items: [:id, :quantity, :price, :name, :participant_id]
          )
        else
          {}
        end
      end
    end
  end
end
