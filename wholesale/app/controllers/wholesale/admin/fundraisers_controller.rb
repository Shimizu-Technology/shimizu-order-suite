# app/controllers/wholesale/admin/fundraisers_controller.rb

module Wholesale
  module Admin
    class FundraisersController < Wholesale::ApplicationController
      before_action :require_admin!
      before_action :set_restaurant_context
      before_action :set_fundraiser, only: [:show, :update, :destroy, :toggle_active, :duplicate]
      
      # GET /wholesale/admin/fundraisers
      # List all fundraisers for the current restaurant with admin features
      def index
        @fundraisers = Wholesale::Fundraiser
          .where(restaurant: current_restaurant)
          .includes(:participants, :items, :orders)
          .order(created_at: :desc)
        
        # Apply search filter if provided
        if params[:search].present?
          search_term = "%#{params[:search]}%"
          @fundraisers = @fundraisers.where(
            "name ILIKE ? OR description ILIKE ? OR contact_email ILIKE ?",
            search_term, search_term, search_term
          )
        end
        
        # Apply status filter if provided
        if params[:status].present? && params[:status] != 'all'
          @fundraisers = @fundraisers.where(status: params[:status])
        end
        
        # Apply pagination
        page = params[:page]&.to_i || 1
        per_page = params[:per_page]&.to_i || 20
        per_page = [per_page, 100].min # Cap at 100 items per page
        
        @fundraisers = @fundraisers.page(page).per(per_page)
        
        render_success(
          fundraisers: @fundraisers.map { |fundraiser| admin_fundraiser_summary(fundraiser) },
          pagination: {
            current_page: @fundraisers.current_page,
            total_pages: @fundraisers.total_pages,
            total_count: @fundraisers.total_count,
            per_page: per_page
          },
          message: "Admin fundraisers list retrieved successfully"
        )
      end
      
      # GET /wholesale/admin/fundraisers/:id
      # Get detailed information about a specific fundraiser for admin
      def show
        render_success(
          fundraiser: admin_fundraiser_detail(@fundraiser),
          message: "Admin fundraiser details retrieved successfully"
        )
      end
      
      # POST /wholesale/admin/fundraisers
      # Create a new fundraiser
      def create
        create_params = fundraiser_params.except(:card_image, :banner_image)
        @fundraiser = Wholesale::Fundraiser.new(create_params)
        @fundraiser.restaurant = current_restaurant
        
        # Generate slug from name if not provided
        @fundraiser.slug = @fundraiser.name.parameterize if @fundraiser.slug.blank?
        
        # Ensure slug is unique for this restaurant
        base_slug = @fundraiser.slug
        counter = 1
        while Wholesale::Fundraiser.where(restaurant: current_restaurant, slug: @fundraiser.slug).exists?
          @fundraiser.slug = "#{base_slug}-#{counter}"
          counter += 1
        end
        
        if @fundraiser.save
          # Process image uploads if present
          process_image_uploads(@fundraiser, fundraiser_params[:card_image], fundraiser_params[:banner_image])
          
          render_success(
            fundraiser: admin_fundraiser_detail(@fundraiser),
            message: "Fundraiser created successfully"
          )
        else
          render_error(
            "Failed to create fundraiser",
            status: :unprocessable_entity,
            errors: @fundraiser.errors.full_messages
          )
        end
      end
      
      # PATCH/PUT /wholesale/admin/fundraisers/:id
      # Update an existing fundraiser
      def update
        update_params = fundraiser_params.except(:card_image, :banner_image)
        
        if @fundraiser.update(update_params)
          # Process image uploads if present
          process_image_uploads(@fundraiser, fundraiser_params[:card_image], fundraiser_params[:banner_image])
          
          # Update slug if name changed and slug wasn't explicitly provided
          if fundraiser_params[:name].present? && !fundraiser_params[:slug].present?
            new_slug = fundraiser_params[:name].parameterize
            if new_slug != @fundraiser.slug
              # Ensure new slug is unique
              base_slug = new_slug
              counter = 1
              while Wholesale::Fundraiser.where(restaurant: current_restaurant, slug: new_slug).where.not(id: @fundraiser.id).exists?
                new_slug = "#{base_slug}-#{counter}"
                counter += 1
              end
              @fundraiser.update_column(:slug, new_slug)
            end
          end
          
          render_success(
            fundraiser: admin_fundraiser_detail(@fundraiser),
            message: "Fundraiser updated successfully"
          )
        else
          render_error(
            "Failed to update fundraiser",
            status: :unprocessable_entity,
            errors: @fundraiser.errors.full_messages
          )
        end
      end
      
      # DELETE /wholesale/admin/fundraisers/:id
      # Delete (soft delete) a fundraiser
      def destroy
        # Check if fundraiser has orders
        if @fundraiser.orders.exists?
          # Soft delete by setting status to cancelled and active to false
          @fundraiser.update!(status: 'cancelled', active: false)
          render_success(message: "Fundraiser cancelled successfully (has existing orders)")
        else
          # Hard delete if no orders exist
          @fundraiser.destroy!
          render_success(message: "Fundraiser deleted successfully")
        end
      end
      
      # PATCH /wholesale/admin/fundraisers/:id/toggle_active
      # Toggle the active status of a fundraiser
      def toggle_active
        @fundraiser.update!(active: !@fundraiser.active)
        
        render_success(
          fundraiser: admin_fundraiser_summary(@fundraiser),
          message: "Fundraiser #{@fundraiser.active? ? 'activated' : 'deactivated'} successfully"
        )
      end
      
      # POST /wholesale/admin/fundraisers/:id/duplicate
      # Create a copy of an existing fundraiser
      def duplicate
        original = @fundraiser
        
        @fundraiser = original.dup
        @fundraiser.name = "#{original.name} (Copy)"
        @fundraiser.slug = "#{original.slug}-copy"
        @fundraiser.status = 'draft'
        @fundraiser.active = false
        @fundraiser.start_date = nil
        @fundraiser.end_date = nil
        
        # Ensure slug is unique
        base_slug = @fundraiser.slug
        counter = 1
        while Wholesale::Fundraiser.where(restaurant: current_restaurant, slug: @fundraiser.slug).exists?
          @fundraiser.slug = "#{base_slug}-#{counter}"
          counter += 1
        end
        
        if @fundraiser.save
          render_success(
            fundraiser: admin_fundraiser_detail(@fundraiser),
            message: "Fundraiser duplicated successfully"
          )
        else
          render_error(
            "Failed to duplicate fundraiser",
            status: :unprocessable_entity,
            errors: @fundraiser.errors.full_messages
          )
        end
      end
      
      private
      
      def set_restaurant_context
        unless current_restaurant
          render_unauthorized('Restaurant context not set.')
        end
      end
      
      def set_fundraiser
        @fundraiser = Wholesale::Fundraiser
          .where(restaurant: current_restaurant)
          .includes(:participants, :items, :orders)
          .find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("Fundraiser not found")
      end
      
      def fundraiser_params
        permitted_params = params.require(:fundraiser).permit(
          :name, :slug, :description, :start_date, :end_date,
          :contact_email, :contact_phone, :active,
          :card_image, :banner_image,
          :pickup_location_name, :pickup_address, :pickup_instructions,
          :pickup_contact_name, :pickup_contact_phone, :pickup_hours,
          settings: [:show_progress_bar]
        )
        
        # Always ensure these settings are set correctly
        permitted_params[:settings] ||= {}
        permitted_params[:settings][:allow_participant_selection] = true
        permitted_params[:settings][:require_participant_selection] = true
        permitted_params[:settings][:show_participant_goals] = false
        
        permitted_params
      end
      
      def process_image_uploads(fundraiser, card_image_file, banner_image_file)
        # Process card image upload
        if card_image_file.present? && card_image_file.respond_to?(:original_filename)
          begin
            # Generate unique filename for card image
            ext = File.extname(card_image_file.original_filename)
            timestamp = Time.now.to_i
            card_filename = "wholesale_fundraiser_card_#{fundraiser.id}_#{timestamp}#{ext}"
            
            # Upload to S3
            card_image_url = S3Uploader.upload(card_image_file, card_filename)
            
            # Update fundraiser with new card image URL
            fundraiser.update_column(:card_image_url, card_image_url)
            
          rescue => e
            Rails.logger.error "[WholesaleFundraisersController] Card image upload failed for fundraiser #{fundraiser.id}: #{e.message}"
            Rails.logger.error "[WholesaleFundraisersController] Backtrace: #{e.backtrace.join("\n")}"
          end
        end
        
        # Process banner image upload
        if banner_image_file.present? && banner_image_file.respond_to?(:original_filename)
          begin
            # Generate unique filename for banner image
            ext = File.extname(banner_image_file.original_filename)
            timestamp = Time.now.to_i
            banner_filename = "wholesale_fundraiser_banner_#{fundraiser.id}_#{timestamp}#{ext}"
            
            # Upload to S3
            banner_image_url = S3Uploader.upload(banner_image_file, banner_filename)
            
            # Update fundraiser with new banner image URL
            fundraiser.update_column(:banner_url, banner_image_url)
            
          rescue => e
            Rails.logger.error "[WholesaleFundraisersController] Banner image upload failed for fundraiser #{fundraiser.id}: #{e.message}"
            Rails.logger.error "[WholesaleFundraisersController] Backtrace: #{e.backtrace.join("\n")}"
          end
        end
      end
      
      # Admin summary format for fundraiser listing
      def admin_fundraiser_summary(fundraiser)
        {
          id: fundraiser.id,
          name: fundraiser.name,
          slug: fundraiser.slug,
          description: fundraiser.description,
          start_date: fundraiser.start_date,
          end_date: fundraiser.end_date,
          contact_email: fundraiser.contact_email,
          contact_phone: fundraiser.contact_phone,
          status: fundraiser.status,
          active: fundraiser.active,
          settings: fundraiser.settings,
          
          # Pickup information
          pickup_location_name: fundraiser.pickup_location_name,
          pickup_address: fundraiser.pickup_address,
          pickup_instructions: fundraiser.pickup_instructions,
          pickup_contact_name: fundraiser.pickup_contact_name,
          pickup_contact_phone: fundraiser.pickup_contact_phone,
          pickup_hours: fundraiser.pickup_hours,
          has_custom_pickup_location: fundraiser.has_custom_pickup_location?,
          pickup_display_name: fundraiser.pickup_display_name,
          pickup_display_address: fundraiser.pickup_display_address,
          
          # Image URLs
          card_image_url: fundraiser.card_image_url,
          banner_url: fundraiser.banner_url,
          has_card_image: fundraiser.has_card_image?,
          has_banner_image: fundraiser.has_banner_image?,
          
          # Computed statistics
          participant_count: fundraiser.participants.active.count,
          item_count: fundraiser.items.active.count,
          total_orders: fundraiser.orders.count,
          total_revenue: fundraiser.total_revenue_cents / 100.0,
          
          # Admin-specific fields
          orders_pending: fundraiser.orders.where(status: 'pending').count,
          orders_processing: fundraiser.orders.where(status: 'processing').count,
          orders_shipped: fundraiser.orders.where(status: 'shipped').count,
          orders_delivered: fundraiser.orders.where(status: 'delivered').count,
          
          # Timestamps
          created_at: fundraiser.created_at,
          updated_at: fundraiser.updated_at,
          
          # URLs
          public_url: "/wholesale/#{fundraiser.slug}",
          admin_url: "/admin/wholesale/fundraisers/#{fundraiser.id}"
        }
      end
      
      # Admin detailed format for specific fundraiser view
      def admin_fundraiser_detail(fundraiser)
        base_data = admin_fundraiser_summary(fundraiser)
        
        base_data.merge({
          # Include related data for detailed view
          participants: fundraiser.participants.active.by_name.map do |participant|
            {
              id: participant.id,
              name: participant.name,
              slug: participant.slug,
              description: participant.description,
              photo_url: participant.photo_url,
              goal_amount: participant.goal_amount,
              current_amount: participant.current_amount,
              goal_progress_percentage: participant.goal_progress_percentage,
              total_orders: participant.total_orders_count,
              total_raised: participant.total_raised,
              active: participant.active,
              created_at: participant.created_at
            }
          end,
          
          items: fundraiser.items.active.by_sort_order.map do |item|
            {
              id: item.id,
              name: item.name,
              description: item.description,
              sku: item.sku,
              price: item.price,
              price_cents: item.price_cents,
              position: item.position,
              sort_order: item.sort_order,
              options: item.options,
              track_inventory: item.track_inventory?,
              stock_quantity: item.stock_quantity,
              low_stock_threshold: item.low_stock_threshold,
              in_stock: item.in_stock?,
              stock_status: item.stock_status,
              total_ordered: item.total_ordered_quantity,
              total_revenue: item.total_revenue_cents / 100.0,
              active: item.active,
              created_at: item.created_at,
              images_count: item.item_images.count
            }
          end,
          
          recent_orders: fundraiser.orders.recent.limit(10).map do |order|
            {
              id: order.id,
              order_number: order.order_number,
              status: order.status,
              payment_status: order.payment_complete? ? 'completed' : 'pending',
              customer_name: order.customer_name,
              customer_email: order.customer_email,
              total: order.total,
              participant_name: order.participant&.name,
              item_count: order.unique_item_count,
              created_at: order.created_at
            }
          end
        })
      end
    end
  end
end