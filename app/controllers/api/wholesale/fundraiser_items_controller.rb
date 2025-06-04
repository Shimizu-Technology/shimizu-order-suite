# app/controllers/api/wholesale/fundraiser_items_controller.rb

module Api
  module Wholesale
    class FundraiserItemsController < Api::Wholesale::ApiController
      include TenantIsolation
      
      before_action :authorize_request, except: [:index, :show]
      before_action :optional_authorize, only: [:index, :show]
      before_action :ensure_tenant_context
      before_action :set_fundraiser
      before_action :set_fundraiser_item, only: [:show, :update, :destroy, :update_inventory, :upload_image]
      
      # GET /api/wholesale/fundraisers/:fundraiser_id/items
      def index
        authorize @fundraiser, :show?
        @items = policy_scope(FundraiserItem).where(fundraiser_id: @fundraiser.id)
        
        # Apply filters if provided
        @items = @items.where(active: true) if params[:active].present? && params[:active] == 'true'
        
        # Apply search if provided
        if params[:search].present?
          search_term = "%#{params[:search]}%"
          @items = @items.where('name ILIKE ? OR description ILIKE ?', search_term, search_term)
        end
        
        # Apply sorting
        sort_by = params[:sort_by] || 'name'
        sort_direction = params[:sort_direction] || 'asc'
        @items = @items.order("#{sort_by} #{sort_direction}")
        
        # Apply pagination
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 25).to_i
        @items = @items.page(page).per(per_page)
        
        render json: {
          items: @items,
          meta: {
            total_count: @items.total_count,
            total_pages: @items.total_pages,
            current_page: @items.current_page,
            per_page: per_page
          }
        }
      end
      
      # GET /api/wholesale/fundraisers/:fundraiser_id/items/:id
      def show
        authorize @item
        render json: @item
      end
      
      # POST /api/wholesale/fundraisers/:fundraiser_id/items
      def create
        # Log the parameters for debugging
        Rails.logger.info "Creating new fundraiser item for fundraiser #{@fundraiser.id}"
        
        # Get the permitted parameters
        item_params = fundraiser_item_params
        Rails.logger.info "Permitted params: #{item_params.inspect}"
        
        # Create the new item
        @item = @fundraiser.fundraiser_items.new(item_params)
        authorize @item
        
        if @item.save
          Rails.logger.info "Successfully created fundraiser item with ID: #{@item.id}"
          
          # Process the image upload after the item is saved
          process_item_image(@item)
          
          # Reload the item to get the updated image_url
          @item.reload
          
          render json: @item, status: :created
        else
          Rails.logger.error "Failed to create fundraiser item: #{@item.errors.full_messages.join(', ')}"
          render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "Exception in create: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: e.message }, status: :unprocessable_entity
      end
      
      # PATCH/PUT /api/wholesale/fundraisers/:fundraiser_id/items/:id
      def update
        authorize @item
        
        # Log the parameters for debugging
        Rails.logger.info "Updating fundraiser item #{@item.id}"
        
        # Get the permitted parameters
        item_params = fundraiser_item_params
        Rails.logger.info "Permitted params: #{item_params.inspect}"
        
        if @item.update(item_params)
          # Process the image upload after the item is updated
          process_item_image(@item)
          
          # Reload the item to get the updated image_url
          @item.reload
          
          render json: @item
        else
          Rails.logger.error "Failed to update fundraiser item: #{@item.errors.full_messages.join(', ')}"
          render json: { errors: @item.errors.full_messages }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error "Exception in update: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: e.message }, status: :unprocessable_entity
      end
      
      # DELETE /api/wholesale/fundraisers/:fundraiser_id/items/:id
      def destroy
        authorize @item
        @item.destroy
        head :no_content
      end
      
      # PATCH /api/wholesale/fundraisers/:fundraiser_id/items/:id/update_inventory
      def update_inventory
        authorize @item, :update?
        quantity_change = params[:quantity_change].to_i
        
        if @item.update_stock(quantity_change)
          render json: @item
        else
          render json: { errors: @item.errors }, status: :unprocessable_entity
        end
      end
      
      # POST /api/wholesale/fundraisers/:fundraiser_id/items/:id/upload_image
      def upload_image
        authorize @item, :update?
        
        # Log the incoming parameters to help debug
        Rails.logger.info "=== FundraiserItemsController#upload_image incoming params ==="
        Rails.logger.info "Image present: #{params[:image].present?}"
        Rails.logger.info "Image class: #{params[:image].class.name if params[:image].present?}"
        
        if params[:image].present?
          process_image_upload(params[:image], @item)
          render json: { image_url: @item.image_url }
        else
          render json: { error: 'No image provided' }, status: :unprocessable_entity
        end
      end
      
      # POST /api/wholesale/fundraisers/:fundraiser_id/items/import_from_menu_items
      def import_from_menu_items
        authorize @fundraiser, :update?
        
        menu_item_ids = params[:menu_item_ids] || []
        
        if menu_item_ids.empty?
          render json: { error: "No menu items selected for import" }, status: :unprocessable_entity
          return
        end
        
        imported_count = 0
        errors = []
        
        menu_item_ids.each do |menu_item_id|
          begin
            # Use policy_scope to ensure tenant isolation
            menu_item = policy_scope(MenuItem).find(menu_item_id)
            
            # Check if item already exists for this fundraiser
            existing_item = @fundraiser.fundraiser_items.find_by(name: menu_item.name)
            
            if existing_item
              errors << { menu_item_id: menu_item_id, message: "Item already exists in this fundraiser" }
              next
            end
            
            # Create new fundraiser item based on menu item
            fundraiser_item = @fundraiser.fundraiser_items.new(
              name: menu_item.name,
              description: menu_item.description,
              price: menu_item.price,
              image_url: menu_item.image_url,
              active: true,
              enable_stock_tracking: menu_item.enable_stock_tracking,
              stock_quantity: menu_item.stock_quantity,
              low_stock_threshold: menu_item.low_stock_threshold
            )
            
            if fundraiser_item.save
              imported_count += 1
            else
              errors << { menu_item_id: menu_item_id, message: fundraiser_item.errors.full_messages.join(", ") }
            end
          rescue ActiveRecord::RecordNotFound
            errors << { menu_item_id: menu_item_id, message: "Menu item not found" }
          rescue => e
            errors << { menu_item_id: menu_item_id, message: e.message }
          end
        end
        
        render json: {
          imported_count: imported_count,
          errors: errors,
          message: "Successfully imported #{imported_count} items"
        }
      end
      
      private
      
      # Process image upload for fundraiser items
      def process_image_upload(file, item)
        Rails.logger.info "Image type: #{file.class.name}"
        
        if file.is_a?(ActionDispatch::Http::UploadedFile) || file.respond_to?(:original_filename)
          # Handle uploaded file
          ext = File.extname(file.original_filename)
          new_filename = "fundraiser_item_#{item.id}_#{Time.now.to_i}#{ext}"
          
          Rails.logger.info "New filename: #{new_filename}"
          
          begin
            # Use the tempfile for the actual upload
            public_url = S3Uploader.upload(file.tempfile || file, new_filename)
            Rails.logger.info "S3 upload successful, public URL: #{public_url}"
            item.update!(image_url: public_url)
          rescue => e
            Rails.logger.error "S3 upload failed: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            render json: { error: 'Failed to upload image' }, status: :unprocessable_entity
          end
        else
          Rails.logger.error "Unsupported file format"
          render json: { error: 'Unsupported file format' }, status: :unprocessable_entity
        end
      end
      
      def set_fundraiser
        @fundraiser = current_restaurant.fundraisers.find(params[:fundraiser_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Fundraiser not found' }, status: :not_found
      end
      
      def set_fundraiser_item
        @item = @fundraiser.fundraiser_items.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Item not found' }, status: :not_found
      end
      
      def fundraiser_item_params
        # First, get the basic parameters without processing the image
        # Include :image in the permitted params to avoid the unpermitted parameter warning
        permitted = params.require(:item).permit(
          :name, :description, :price, :image_url, :active, :image,
          :enable_stock_tracking, :stock_quantity, :low_stock_threshold
        )
        
        # Remove the image from the permitted params as we'll handle it separately
        # This ensures we're not trying to save the image directly to the database
        permitted.delete(:image)
        
        permitted
      end
      
      # Process the image and update the item with the image URL
      def process_item_image(item)
        # Check if an image was uploaded
        image_param = params[:item][:image] if params[:item].present?
        
        return unless image_param.present?
        
        Rails.logger.info "=== Processing image for item #{item.id} ==="
        Rails.logger.info "Image class: #{image_param.class.name}"
        
        if image_param.is_a?(String) && image_param.start_with?('data:image')
          # Handle base64 encoded image
          content_type = image_param.split(';')[0].split(':')[1]
          extension = content_type.split('/')[1]
          extension = 'jpg' if extension == 'jpeg'
          
          # Extract the actual image data from the base64 string
          image_data = image_param.split(',')[1]
          decoded_image = Base64.decode64(image_data)
          
          # Create a temp file
          temp_file = Tempfile.new(['fundraiser_item_image', ".#{extension}"])
          temp_file.binmode
          temp_file.write(decoded_image)
          temp_file.rewind
          
          # Generate a simple filename
          new_filename = "fundraiser_item_#{item.id}_#{Time.now.to_i}.#{extension}"
          
          begin
            # Upload to S3
            public_url = S3Uploader.upload(temp_file, new_filename)
            item.update!(image_url: public_url)
            Rails.logger.info "S3 upload successful, public URL: #{public_url}"
          rescue => e
            Rails.logger.error "S3 upload failed: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
          ensure
            # Clean up temp file
            temp_file.close
            temp_file.unlink
          end
        elsif image_param.is_a?(ActionDispatch::Http::UploadedFile) || image_param.respond_to?(:original_filename)
          # Handle uploaded file
          ext = File.extname(image_param.original_filename)
          new_filename = "fundraiser_item_#{item.id}_#{Time.now.to_i}#{ext}"
          
          begin
            # Upload to S3
            public_url = S3Uploader.upload(image_param.tempfile || image_param, new_filename)
            item.update!(image_url: public_url)
            Rails.logger.info "S3 upload successful, public URL: #{public_url}"
          rescue => e
            Rails.logger.error "S3 upload failed: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
          end
        end
      end
      
      # Process base64 encoded image and update the image_url
      def process_base64_image(base64_string, permitted_params)
        content_type = base64_string.split(';')[0].split(':')[1]
        extension = content_type.split('/')[1]
        extension = 'jpg' if extension == 'jpeg'
        
        # Extract the actual image data from the base64 string
        image_data = base64_string.split(',')[1]
        decoded_image = Base64.decode64(image_data)
        
        # Create a temp file
        temp_file = Tempfile.new(['fundraiser_item_image', ".#{extension}"])
        temp_file.binmode
        temp_file.write(decoded_image)
        temp_file.rewind
        
        # Generate a simple filename
        new_filename = "fundraiser_item_#{Time.now.to_i}.#{extension}"
        
        begin
          # Upload to S3
          public_url = S3Uploader.upload(temp_file, new_filename)
          permitted_params[:image_url] = public_url
        rescue => e
          Rails.logger.error "S3 upload failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        ensure
          # Clean up temp file
          temp_file.close
          temp_file.unlink
        end
      end
      
      # For direct API testing with curl or Postman
      def image_params
        params.permit(:image)
      end
    end
  end
end
