class MerchandiseItemsController < ApplicationController
  # 1) For index & show, optional_authorize => public can see
  before_action :optional_authorize, only: [ :index, :show ]

  # 2) For other actions, require token + admin
  before_action :authorize_request, except: [ :index, :show ]

  # Mark all actions as public endpoints that don't require restaurant context
  def public_endpoint?
    true
  end

  # GET /merchandise_items
  def index
    # Get the restaurant from the params
    restaurant_id = params[:restaurant_id]
    restaurant = Restaurant.find_by(id: restaurant_id) if restaurant_id.present?

    # If admin AND params[:show_all] => show all. Otherwise only available.
    if is_admin? && params[:show_all].present?
      base_scope = MerchandiseItem.all
    else
      base_scope = MerchandiseItem.where(available: true)
    end

    # Filter by collection_id if provided
    if params[:collection_id].present?
      base_scope = base_scope.where(merchandise_collection_id: params[:collection_id])
    # Otherwise, filter by the restaurant's current collection if available
    elsif restaurant&.current_merchandise_collection_id.present?
      base_scope = base_scope.where(merchandise_collection_id: restaurant.current_merchandise_collection_id)
    end

    # Sort by name
    base_scope = base_scope.order(:name)

    items = base_scope.includes(:merchandise_variants)

    # Include collection name for each item when returning all items
    if params[:include_collection_names].present?
      items_with_collection = items.map do |item|
        item_json = item.as_json(include_variants: true)
        item_json["collection_name"] = item.merchandise_collection&.name
        item_json
      end
      render json: items_with_collection
    else
      render json: items.as_json(include_variants: true)
    end
  end

  # GET /merchandise_items/:id
  def show
    item = MerchandiseItem.includes(:merchandise_variants).find(params[:id])
    render json: item.as_json(include_variants: true)
  end

  # POST /merchandise_items
  def create
    Rails.logger.info "=== MerchandiseItemsController#create ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @merchandise_item = MerchandiseItem.new(merchandise_item_params.except(:image, :second_image))

    if @merchandise_item.save
      Rails.logger.info "Created MerchandiseItem => #{@merchandise_item.inspect}"

      # Handle image upload if present
      file = merchandise_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        ext = File.extname(file.original_filename)
        new_filename = "merchandise_item_#{@merchandise_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        @merchandise_item.update!(image_url: public_url)
      end

      # Handle second image upload if present
      second_file = merchandise_item_params[:second_image]
      if second_file.present? && second_file.respond_to?(:original_filename)
        ext = File.extname(second_file.original_filename)
        new_filename = "merchandise_item_second_#{@merchandise_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(second_file, new_filename)
        @merchandise_item.update!(second_image_url: public_url)
      end

      render json: @merchandise_item, status: :created
    else
      Rails.logger.info "Failed to create => #{@merchandise_item.errors.full_messages.inspect}"
      render json: { errors: @merchandise_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /merchandise_items/:id
  def update
    Rails.logger.info "=== MerchandiseItemsController#update ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @merchandise_item = MerchandiseItem.find(params[:id])
    Rails.logger.info "Updating MerchandiseItem => #{@merchandise_item.id}"

    if @merchandise_item.update(merchandise_item_params.except(:image, :second_image))
      Rails.logger.info "Update success => #{@merchandise_item.inspect}"

      # Handle image if present
      file = merchandise_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        ext = File.extname(file.original_filename)
        new_filename = "merchandise_item_#{@merchandise_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        @merchandise_item.update!(image_url: public_url)
      end

      # Handle second image if present
      second_file = merchandise_item_params[:second_image]
      if second_file.present? && second_file.respond_to?(:original_filename)
        ext = File.extname(second_file.original_filename)
        new_filename = "merchandise_item_second_#{@merchandise_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(second_file, new_filename)
        @merchandise_item.update!(second_image_url: public_url)
        Rails.logger.info "merchandise_item updated with second image => second_image_url: #{public_url}"
      end

      render json: @merchandise_item
    else
      Rails.logger.info "Update failed => #{@merchandise_item.errors.full_messages.inspect}"
      render json: { errors: @merchandise_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /merchandise_items/:id
  def destroy
    Rails.logger.info "=== MerchandiseItemsController#destroy ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    merchandise_item = MerchandiseItem.find(params[:id])
    Rails.logger.info "Destroying MerchandiseItem => #{merchandise_item.id}, image_url: #{merchandise_item.image_url.inspect}"

    merchandise_item.destroy
    Rails.logger.info "Destroyed MerchandiseItem => #{merchandise_item.id}"

    head :no_content
  end

  # (Optional) POST /merchandise_items/:id/upload_image
  def upload_image
    Rails.logger.info "=== MerchandiseItemsController#upload_image ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    merchandise_item = MerchandiseItem.find(params[:id])
    file = params[:image]
    unless file
      Rails.logger.info "No file param"
      return render json: { error: "No image file uploaded" }, status: :unprocessable_entity
    end

    ext = File.extname(file.original_filename)
    new_filename = "merchandise_item_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
    public_url   = S3Uploader.upload(file, new_filename)
    merchandise_item.update!(image_url: public_url)

    Rails.logger.info "merchandise_item updated => image_url: #{merchandise_item.image_url.inspect}"
    render json: merchandise_item, status: :ok
  end

  # POST /merchandise_items/:id/upload_second_image
  def upload_second_image
    Rails.logger.info "=== MerchandiseItemsController#upload_second_image ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    merchandise_item = MerchandiseItem.find(params[:id])
    file = params[:image]
    unless file
      Rails.logger.info "No file param"
      return render json: { error: "No image file uploaded" }, status: :unprocessable_entity
    end

    ext = File.extname(file.original_filename)
    new_filename = "merchandise_item_second_#{merchandise_item.id}_#{Time.now.to_i}#{ext}"
    public_url   = S3Uploader.upload(file, new_filename)
    merchandise_item.update!(second_image_url: public_url)

    Rails.logger.info "merchandise_item updated => second_image_url: #{merchandise_item.second_image_url.inspect}"
    render json: merchandise_item, status: :ok
  end

  def merchandise_item_params
    params.require(:merchandise_item).permit(
      :name,
      :description,
      :base_price,
      :available,
      :merchandise_collection_id,
      :image_url,
      :image,
      :second_image_url,
      :second_image,
      :stock_status,
      :low_stock_threshold,
      :status_note
    )
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
