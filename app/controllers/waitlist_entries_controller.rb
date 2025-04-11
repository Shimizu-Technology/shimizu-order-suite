# app/controllers/waitlist_entries_controller.rb
class WaitlistEntriesController < ApplicationController
  include TenantIsolation
  
  before_action :authorize_request
  before_action :ensure_tenant_context

  def index
    # Only staff/admin/super_admin can list the entire waitlist
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    # Prepare filter parameters
    filter_params = {}
    
    if params[:date].present?
      # Handle both simple string and nested parameter formats
      date_param = params[:date].is_a?(ActionController::Parameters) ? params[:date][:date] : params[:date]
      filter_params[:date] = date_param
    end
    
    # Add other filters if present
    [:status, :customer_name, :phone, :page, :per_page].each do |param|
      filter_params[param] = params[param] if params[param].present?
    end
    
    result = waitlist_entry_service.list_entries(filter_params)
    
    if result[:success]
      render json: result[:entries].as_json(
        only: [
          :id,
          :restaurant_id,
          :contact_name,
          :party_size,
          :check_in_time,
          :status,
          :contact_phone,
          :created_at,
          :updated_at
        ],
        methods: :seat_labels
      )
    else
      render json: { error: result[:errors].join(', ') }, status: result[:status] || :internal_server_error
    end
  end

  def show
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    result = waitlist_entry_service.find_entry(params[:id])
    
    if result[:success]
      render json: result[:entry].as_json(
        only: [
          :id,
          :restaurant_id,
          :contact_name,
          :party_size,
          :check_in_time,
          :status,
          :contact_phone,
          :created_at,
          :updated_at,
          :estimated_wait_minutes,
          :notification_count,
          :last_notified_at,
          :notes
        ],
        methods: :seat_labels
      )
    else
      render json: { error: result[:errors].join(', ') }, status: result[:status] || :not_found
    end
  end

  def create
    # Prepare the entry parameters
    create_params = waitlist_entry_params.to_h
    
    # Set the restaurant_id to the current restaurant
    create_params[:restaurant_id] = current_restaurant.id
    
    # Create the entry using the service
    result = waitlist_entry_service.create_entry(create_params)
    
    if result[:success]
      render json: result[:entry], status: :created
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def update
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    result = waitlist_entry_service.update_entry(params[:id], waitlist_entry_params.to_h)
    
    if result[:success]
      render json: result[:entry]
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  def destroy
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    result = waitlist_entry_service.delete_entry(params[:id])
    
    if result[:success]
      head :no_content
    else
      render json: { errors: result[:errors] }, status: result[:status] || :unprocessable_entity
    end
  end

  private

  def waitlist_entry_params
    params.require(:waitlist_entry).permit(
      :restaurant_id,
      :contact_name,
      :party_size,
      :check_in_time,
      :status,
      :contact_phone,
      :notes,
      :estimated_wait_minutes
    )
  end
  
  def waitlist_entry_service
    @waitlist_entry_service ||= begin
      service = WaitlistEntryService.new(current_restaurant)
      service.current_user = current_user
      service
    end
  end
  
  def ensure_tenant_context
    unless current_restaurant.present?
      render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
    end
  end
end
