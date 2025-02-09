# app/controllers/menu_items_controller.rb
class MenuItemsController < ApplicationController
  before_action :authorize_request, except: [:index, :show]

  # GET /menu_items
  def index
    items_scope = if params[:category].present?
                    MenuItem.where(category: params[:category], available: true)
                  else
                    MenuItem.where(available: true)
                  end

    items = items_scope.includes(option_groups: :options)

    # Render each item with numeric :id and nested option_groups
    render json: items.as_json(
      only: [:id, :name, :description, :price, :category, :image_url],
      include: {
        option_groups: {
          include: {
            options: {
              only: [:id, :name, :available],
              methods: [:additional_price_float]  # so we get a float for additional_price
            }
          }
        }
      }
    )
  end

  # GET /menu_items/:id
  def show
    # Eager-load the option_groups and their options
    item = MenuItem.includes(option_groups: :options).find(params[:id])

    render json: item.as_json(
      only: [:id, :name, :description, :price, :category, :image_url],
      include: {
        option_groups: {
          include: {
            options: {
              only: [:id, :name, :available],
              methods: [:additional_price_float]
            }
          }
        }
      }
    )
  end

  # POST /menu_items
  def create
    Rails.logger.info "=== MenuItemsController#create ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    # Note: No attempt to set :id manually, we let Rails pick an integer ID
    @menu_item = MenuItem.new(menu_item_params.except(:image))
    if @menu_item.save
      Rails.logger.info "Created MenuItem => #{@menu_item.inspect}"

      file = menu_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        ext = File.extname(file.original_filename)
        new_filename = "menu_item_#{@menu_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        @menu_item.update!(image_url: public_url)
      end

      render json: @menu_item, status: :created
    else
      Rails.logger.info "Failed to create => #{@menu_item.errors.full_messages.inspect}"
      render json: { errors: @menu_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /menu_items/:id
  def update
    Rails.logger.info "=== MenuItemsController#update ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    @menu_item = MenuItem.find(params[:id])
    Rails.logger.info "Updating MenuItem => #{@menu_item.id}"

    if @menu_item.update(menu_item_params.except(:image))
      Rails.logger.info "Update success => #{@menu_item.inspect}"

      file = menu_item_params[:image]
      if file.present? && file.respond_to?(:original_filename)
        ext = File.extname(file.original_filename)
        new_filename = "menu_item_#{@menu_item.id}_#{Time.now.to_i}#{ext}"
        public_url   = S3Uploader.upload(file, new_filename)
        @menu_item.update!(image_url: public_url)
      end

      render json: @menu_item
    else
      Rails.logger.info "Update failed => #{@menu_item.errors.full_messages.inspect}"
      render json: { errors: @menu_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /menu_items/:id
  def destroy
    Rails.logger.info "=== MenuItemsController#destroy ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:id])
    Rails.logger.info "Destroying MenuItem => #{menu_item.id}, current image_url => #{menu_item.image_url.inspect}"

    menu_item.destroy
    Rails.logger.info "Destroyed MenuItem => #{menu_item.id}"

    head :no_content
  end

  # POST /menu_items/:id/upload_image
  def upload_image
    Rails.logger.info "=== MenuItemsController#upload_image ==="
    return render json: { error: "Forbidden" }, status: :forbidden unless is_admin?

    menu_item = MenuItem.find(params[:id])
    file = params[:image]
    unless file
      Rails.logger.info "No file param"
      return render json: { error: 'No image file uploaded' }, status: :unprocessable_entity
    end

    ext = File.extname(file.original_filename)
    new_filename = "menu_item_#{menu_item.id}_#{Time.now.to_i}#{ext}"
    public_url   = S3Uploader.upload(file, new_filename)
    menu_item.update!(image_url: public_url)

    Rails.logger.info "menu_item updated => image_url: #{menu_item.image_url.inspect}"
    render json: menu_item, status: :ok
  end

  private

  def menu_item_params
    params.require(:menu_item).permit(
      :name,
      :description,
      :price,
      :available,
      :menu_id,
      :category,
      :image_url,
      :image  # allow file upload param
    )
  end

  def is_admin?
    current_user && current_user.role.in?(%w[admin super_admin])
  end
end
