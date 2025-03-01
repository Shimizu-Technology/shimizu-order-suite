# app/controllers/admin/notification_templates_controller.rb
class Admin::NotificationTemplatesController < ApplicationController
  before_action :authorize_request
  before_action :require_admin
  before_action :set_notification_template, only: [:show, :update, :destroy]
  
  # Override the public_endpoint? method from RestaurantScope
  def public_endpoint?
    true
  end

  # GET /admin/notification_templates
  def index
    # Handle nested params structure if present
    restaurant_id = params[:restaurant_id] || params.dig(:params, :restaurant_id) || current_user.restaurant_id
    frontend_id = params[:frontend_id] || params.dig(:params, :frontend_id)
    include_defaults = params[:include_defaults] == 'true' || params.dig(:params, :include_defaults) == 'true'
    
    # Get templates for the current restaurant
    @templates = NotificationTemplate.where(restaurant_id: restaurant_id)
    
    # Filter by frontend_id if provided
    @templates = @templates.where(frontend_id: frontend_id) if frontend_id.present?
    
    # Include default templates if requested
    if include_defaults
      default_templates = NotificationTemplate.where(restaurant_id: nil)
      
      # Filter default templates by frontend_id if provided
      default_templates = default_templates.where(frontend_id: frontend_id) if frontend_id.present?
      
      @templates = @templates.or(default_templates)
    end
    
    render json: @templates
  end

  # GET /admin/notification_templates/:id
  def show
    render json: @notification_template
  end

  # POST /admin/notification_templates
  def create
    # If this is a clone from a default template
    if params[:clone_from_default].present?
      @notification_template = NotificationTemplate.clone_for_restaurant(
        params[:notification_type],
        params[:channel],
        current_user.restaurant_id,
        params[:frontend_id]
      )
      
      if @notification_template
        render json: @notification_template, status: :created
      else
        render json: { error: "Default template not found" }, status: :not_found
      end
      return
    end
    
    # Otherwise, create a new template
    @notification_template = NotificationTemplate.new(notification_template_params)
    @notification_template.restaurant_id = current_user.restaurant_id
    
    if @notification_template.save
      render json: @notification_template, status: :created
    else
      render json: { errors: @notification_template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /admin/notification_templates/:id
  def update
    # Only allow updating templates for the current restaurant
    unless @notification_template.restaurant_id == current_user.restaurant_id
      return render json: { error: "Cannot modify default templates" }, status: :forbidden
    end
    
    if @notification_template.update(notification_template_params)
      render json: @notification_template
    else
      render json: { errors: @notification_template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /admin/notification_templates/:id
  def destroy
    # Only allow deleting templates for the current restaurant
    unless @notification_template.restaurant_id == current_user.restaurant_id
      return render json: { error: "Cannot delete default templates" }, status: :forbidden
    end
    
    @notification_template.destroy
    head :no_content
  end

  # POST /admin/notification_templates/preview
  def preview
    # This endpoint allows previewing a template with sample data
    template_type = params[:notification_type]
    channel = params[:channel]
    content = params[:content]
    subject = params[:subject]
    
    # Get frontend_id from params
    frontend_id = params[:frontend_id] || current_user.restaurant.frontend_id || 'hafaloha'
    
    # Sample data for preview
    sample_data = {
      restaurant_name: current_user.restaurant.name,
      restaurant_address: current_user.restaurant.address,
      restaurant_phone: current_user.restaurant.phone_number,
      customer_name: "Sample Customer",
      order_id: "12345",
      total: "15.95",
      items: "1x Burger, 1x Fries",
      special_instructions: "Extra ketchup",
      contact_phone: "+1234567890",
      eta: "5:30 PM",
      contact_name: "John Smith",
      reservation_time: "March 15 at 7:00 PM",
      party_size: "4",
      deposit_amount: "10.00",
      frontend_id: frontend_id
    }
    
    # Add frontend-specific data
    case frontend_id
    when 'hafaloha'
      sample_data.merge!(
        brand_color: '#c1902f',
        logo_url: 'https://hafaloha.com/logo.png',
        footer_text: 'Mahalo for your order!'
      )
    when 'sushi_spot'
      sample_data.merge!(
        brand_color: '#e74c3c',
        logo_url: 'https://sushi-spot.com/logo.png',
        footer_text: 'Thank you for your order!'
      )
    else
      sample_data.merge!(
        brand_color: '#333333',
        logo_url: '',
        footer_text: 'Thank you for your business!'
      )
    end
    
    # Render the template
    if channel == 'email'
      rendered_subject = TemplateRenderer.render(subject, sample_data)
      rendered_content = TemplateRenderer.render(content, sample_data)
      
      render json: {
        subject: rendered_subject,
        content: rendered_content
      }
    else
      rendered_content = TemplateRenderer.render(content, sample_data)
      
      render json: {
        content: rendered_content
      }
    end
  end

  private
  
  def set_notification_template
    @notification_template = NotificationTemplate.find(params[:id])
  end
  
  def notification_template_params
    params.require(:notification_template).permit(
      :notification_type,
      :channel,
      :subject,
      :content,
      :sender_name,
      :frontend_id,
      :active
    )
  end
  
  def require_admin
    unless current_user&.role.in?(%w[admin super_admin])
      render json: { error: "Admin access required" }, status: :forbidden
    end
  end
end
