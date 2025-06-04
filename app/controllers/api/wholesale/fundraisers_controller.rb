# app/controllers/api/wholesale/fundraisers_controller.rb

module Api
  module Wholesale
    class FundraisersController < Api::Wholesale::ApiController
      include TenantIsolation
      
      before_action :authorize_request, except: [:index, :show, :by_slug]
      before_action :optional_authorize, only: [:index, :show, :by_slug]
      before_action :ensure_tenant_context
      before_action :set_fundraiser, only: [:show, :update, :destroy]
      
      # GET /api/wholesale/fundraisers
      def index
        @fundraisers = policy_scope(Fundraiser)
        
        # Apply filters if provided
        @fundraisers = @fundraisers.where(active: true) if params[:active].present? && params[:active] == 'true'
        @fundraisers = @fundraisers.where(featured: true) if params[:featured].present? && params[:featured] == 'true'
        
        # Filter by date range if provided
        if params[:current].present? && params[:current] == 'true'
          now = Time.current
          @fundraisers = @fundraisers.where(active: true)
            .where('(start_date IS NULL OR start_date <= ?)', now)
            .where('(end_date IS NULL OR end_date >= ?)', now)
        end
        
        # Apply search if provided
        if params[:search].present?
          search_term = "%#{params[:search]}%"
          @fundraisers = @fundraisers.where('name ILIKE ? OR slug ILIKE ? OR description ILIKE ?', 
                                           search_term, search_term, search_term)
        end
        
        # Apply sorting
        sort_by = params[:sort_by] || 'created_at'
        sort_direction = params[:sort_direction] || 'desc'
        @fundraisers = @fundraisers.order("#{sort_by} #{sort_direction}")
        
        # Apply pagination
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 25).to_i
        @fundraisers = @fundraisers.page(page).per(per_page)
        
        render json: {
          fundraisers: @fundraisers,
          meta: {
            total_count: @fundraisers.total_count,
            total_pages: @fundraisers.total_pages,
            current_page: @fundraisers.current_page,
            per_page: per_page
          }
        }
      end
      
      # GET /api/wholesale/fundraisers/:id
      def show
        authorize @fundraiser
        render json: @fundraiser, include: ['fundraiser_participants', 'fundraiser_items']
      end
      
      # GET /api/wholesale/fundraisers/by_slug/:slug
      def by_slug
        @fundraiser = policy_scope(Fundraiser).find_by!(slug: params[:slug])
        authorize @fundraiser
        render json: @fundraiser, include: ['fundraiser_participants', 'fundraiser_items']
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Fundraiser not found' }, status: :not_found
      end
      
      # POST /api/wholesale/fundraisers
      def create
        # Log the incoming parameters to help debug
        Rails.logger.info "=== FundraisersController#create incoming params ==="
        Rails.logger.info "Fundraiser params keys: #{params[:fundraiser].keys}"
        
        # Create the fundraiser without the image and banner_image_url
        @fundraiser = current_restaurant.fundraisers.new(fundraiser_params)
        authorize @fundraiser
        
        if @fundraiser.save
          # Handle image upload if present
          file = params[:fundraiser][:image]
          Rails.logger.info "=== FundraisersController#create image processing ==="
          Rails.logger.info "Image present: #{file.present?}"
          Rails.logger.info "Image class: #{file.class.name if file.present?}"
          Rails.logger.info "Params: #{params[:fundraiser].keys}"
          
          # Check if banner_image_url is also being sent (which would be problematic)
          if params[:fundraiser][:banner_image_url].present?
            Rails.logger.warn "WARNING: banner_image_url is being sent directly from frontend. This should be handled by the backend."
            Rails.logger.warn "Banner image URL value: #{params[:fundraiser][:banner_image_url][0..50]}...(truncated)"
          end
          
          if file.present?
            process_image_upload(file, @fundraiser)
          end
          
          render json: @fundraiser, status: :created
        else
          render json: { errors: @fundraiser.errors }, status: :unprocessable_entity
        end
      end
      
      # PATCH/PUT /api/wholesale/fundraisers/:id
      def update
        authorize @fundraiser
        # Log the incoming parameters to help debug
        Rails.logger.info "=== FundraisersController#update incoming params ==="
        Rails.logger.info "Fundraiser params keys: #{params[:fundraiser].keys}"
        
        if @fundraiser.update(fundraiser_params)
          # Handle image upload if present
          file = params[:fundraiser][:image]
          Rails.logger.info "=== FundraisersController#update image processing ==="
          Rails.logger.info "Image present: #{file.present?}"
          Rails.logger.info "Image class: #{file.class.name if file.present?}"
          Rails.logger.info "Params: #{params[:fundraiser].keys}"
          
          # Check if banner_image_url is also being sent (which would be problematic)
          if params[:fundraiser][:banner_image_url].present?
            Rails.logger.warn "WARNING: banner_image_url is being sent directly from frontend. This should be handled by the backend."
            Rails.logger.warn "Banner image URL value: #{params[:fundraiser][:banner_image_url][0..50]}...(truncated)"
          end
          
          if file.present?
            process_image_upload(file, @fundraiser)
          end
          
          render json: @fundraiser
        else
          render json: { errors: @fundraiser.errors }, status: :unprocessable_entity
        end
      end
      
      # DELETE /api/wholesale/fundraisers/:id
      def destroy
        authorize @fundraiser
        @fundraiser.destroy
        head :no_content
      end
      
      # POST /api/wholesale/fundraisers/:id/toggle_active
      def toggle_active
        @fundraiser = policy_scope(Fundraiser).find(params[:id])
        authorize @fundraiser, :update?
        @fundraiser.update(active: !@fundraiser.active)
        render json: @fundraiser
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Fundraiser not found' }, status: :not_found
      end
      
      private
      
      # Process image upload for both create and update actions
      def process_image_upload(file, fundraiser)
        # Handle base64 encoded images
        Rails.logger.info "Image type: #{file.class.name}"
        Rails.logger.info "Is string: #{file.is_a?(String)}"
        Rails.logger.info "Starts with data:image: #{file.is_a?(String) && file.start_with?('data:image')}"
        
        if file.is_a?(String) && file.start_with?('data:image')
          # Handle base64 encoded image
          process_base64_image(file, fundraiser)
        elsif file.is_a?(ActionDispatch::Http::UploadedFile)
          # Handle uploaded file from multipart form
          process_uploaded_file(file, fundraiser)
        elsif file.respond_to?(:original_filename)
          # Handle other file upload objects
          process_regular_file(file, fundraiser)
        end
      end
      
      # Process base64 encoded image
      def process_base64_image(file, fundraiser)
        content_type = file.split(';')[0].split(':')[1]
        extension = content_type.split('/')[1]
        extension = 'jpg' if extension == 'jpeg'
        
        Rails.logger.info "Content type: #{content_type}"
        Rails.logger.info "Extension: #{extension}"
        
        # Extract the actual image data from the base64 string
        image_data = file.split(',')[1]
        decoded_image = Base64.decode64(image_data)
        
        Rails.logger.info "Decoded image size: #{decoded_image.bytesize} bytes"
        
        # Create a temp file
        temp_file = Tempfile.new(['fundraiser_image', ".#{extension}"])
        temp_file.binmode
        temp_file.write(decoded_image)
        temp_file.rewind
        
        Rails.logger.info "Temp file created: #{temp_file.path}"
        
        # Generate a simple filename
        new_filename = "fundraiser_#{fundraiser.id}_#{Time.now.to_i}.#{extension}"
        Rails.logger.info "New filename: #{new_filename}"
        
        # Upload to S3
        begin
          public_url = S3Uploader.upload(temp_file, new_filename)
          Rails.logger.info "S3 upload successful, public URL: #{public_url}"
          fundraiser.update!(banner_image_url: public_url)
        rescue => e
          Rails.logger.error "S3 upload failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
        
        # Clean up temp file
        temp_file.close
        temp_file.unlink
      end
      
      # Process ActionDispatch::Http::UploadedFile
      def process_uploaded_file(file, fundraiser)
        Rails.logger.info "Processing ActionDispatch::Http::UploadedFile: #{file.original_filename}"
        ext = File.extname(file.original_filename)
        new_filename = "fundraiser_#{fundraiser.id}_#{Time.now.to_i}#{ext}"
        
        Rails.logger.info "New filename: #{new_filename}"
        
        begin
          # Use the tempfile for the actual upload
          public_url = S3Uploader.upload(file.tempfile, new_filename)
          Rails.logger.info "S3 upload successful, public URL: #{public_url}"
          fundraiser.update!(banner_image_url: public_url)
        rescue => e
          Rails.logger.error "S3 upload failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end
      
      # Process regular file upload object
      def process_regular_file(file, fundraiser)
        Rails.logger.info "Processing regular file: #{file.original_filename}"
        ext = File.extname(file.original_filename)
        new_filename = "fundraiser_#{fundraiser.id}_#{Time.now.to_i}#{ext}"
        
        Rails.logger.info "New filename: #{new_filename}"
        
        begin
          public_url = S3Uploader.upload(file, new_filename)
          Rails.logger.info "S3 upload successful, public URL: #{public_url}"
          fundraiser.update!(banner_image_url: public_url)
        rescue => e
          Rails.logger.error "S3 upload failed: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
        end
      end
      
      def set_fundraiser
        @fundraiser = current_restaurant.fundraisers.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Fundraiser not found' }, status: :not_found
      end
      
      def fundraiser_params
        # We need to permit :image to avoid unpermitted parameter warnings,
        # but we'll handle it separately in the create/update actions
        permitted_params = params.require(:fundraiser).permit(
          :name, :slug, :description, :banner_image_url, :active, :featured,
          :start_date, :end_date, :restaurant_id, :image, :order_code
        )
        
        # Remove the image from the params hash since it's not a database column
        # We'll handle it separately in the create/update actions
        permitted_params.delete(:image) if permitted_params.key?(:image)
        
        permitted_params
      end
    end
  end
end
