class VipAccessController < ApplicationController
  before_action :authorize_request, except: [ :validate_code ]
  before_action :set_restaurant, only: [ :validate_code ]
  before_action :set_current_restaurant, except: [ :validate_code ]
  before_action :set_vip_code, only: [ :deactivate_code, :update_code, :archive_code ]

  # Override public_endpoint? to mark codes and generate_codes as public endpoints
  def public_endpoint?
    action_name.in?([ "codes", "generate_codes", "deactivate_code", "update_code", "validate_code", "archive_code", "code_usage", "send_vip_code_email", "bulk_send_vip_codes", "send_existing_vip_codes", "search_by_email" ])
  end

  def validate_code
    code = params[:code]

    if code.blank?
      return render json: { valid: false, message: "VIP code is required" }, status: :bad_request
    end

    # Check if the restaurant has VIP-only checkout enabled
    unless @restaurant.vip_only_checkout?
      return render json: { valid: true, message: "VIP access not required" }
    end

    # Find the VIP code
    vip_code = @restaurant.vip_access_codes.find_by(code: code)

    # Check if the code exists and is available
    if vip_code && vip_code.available?
      render json: { valid: true, message: "Valid VIP code" }
    else
      # Provide a more specific error message if the code exists but has reached its usage limit
      if vip_code && vip_code.max_uses && vip_code.current_uses >= vip_code.max_uses
        render json: { valid: false, message: "This VIP code has reached its maximum usage limit" }, status: :unauthorized
      else
        render json: { valid: false, message: "Invalid VIP code" }, status: :unauthorized
      end
    end
  end

  # GET /vip_access/codes
  def codes
    # By default, don't show archived codes unless explicitly requested
    if params[:include_archived] == "true"
      @codes = @restaurant.vip_access_codes
    else
      @codes = @restaurant.vip_access_codes.where(archived: false)
    end

    # Sort by creation date (newest first) by default
    @codes = @codes.order(created_at: :desc)

    render json: @codes
  end

  # POST /vip_access/generate_codes
  def generate_codes
    # Check if the user has permission
    unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == @restaurant.id
      return render json: { error: "Forbidden" }, status: :forbidden
    end

    options = {
      name: params[:name],
      prefix: params[:prefix],
      max_uses: params[:max_uses].present? ? params[:max_uses].to_i : nil
    }

    if params[:batch]
      # Generate multiple individual codes
      count = params[:count].to_i || 1
      @vip_codes = VipCodeGenerator.generate_codes(@restaurant, count, options)
      render json: @vip_codes
    else
      # Generate a single group code
      @vip_code = VipCodeGenerator.generate_group_code(@restaurant, options)
      render json: @vip_code
    end
  end

  # DELETE /vip_access/codes/:id
  def deactivate_code
    @vip_code.update!(is_active: false)
    render json: { message: "VIP code deactivated successfully" }
  end

  # PATCH /vip_access/codes/:id
  def update_code
    # Check if the params are nested under vip_code or directly in the params
    if params[:vip_code].present?
      vip_code_params = params.require(:vip_code).permit(:name, :max_uses, :expires_at, :is_active)
    else
      vip_code_params = params.permit(:name, :max_uses, :expires_at, :is_active)
    end

    @vip_code.update!(vip_code_params)
    render json: @vip_code
  end

  # POST /vip_access/codes/:id/archive
  def archive_code
    @vip_code.update!(archived: true, is_active: false)
    render json: { message: "VIP code archived successfully" }
  end

  # GET /vip_access/codes/:id/usage
  def code_usage
    @vip_code = VipAccessCode.find(params[:id])

    # Ensure the VIP code belongs to the current restaurant
    unless @vip_code.restaurant_id == @restaurant&.id
      render json: { error: "VIP code not found" }, status: :not_found
      return
    end

    # Get orders that used this VIP code
    @orders = @vip_code.orders.includes(:user).order(created_at: :desc)

    # Get recipients of this VIP code
    @recipients = @vip_code.vip_code_recipients.order(sent_at: :desc)

    # Prepare the response with code details, recipient information, and order information
    response = {
      code: @vip_code.as_json,
      usage_count: @orders.count,
      recipients: @recipients.map do |recipient|
        {
          email: recipient.email,
          sent_at: recipient.sent_at
        }
      end,
      orders: @orders.map do |order|
        {
          id: order.id,
          created_at: order.created_at,
          status: order.status,
          total: order.total.to_f,
          customer_name: order.contact_name,
          customer_email: order.contact_email,
          customer_phone: order.contact_phone,
          user: order.user ? { id: order.user.id, name: "#{order.user.first_name} #{order.user.last_name}" } : nil,
          items: order.items.map do |item|
            {
              name: item["name"],
              quantity: item["quantity"],
              price: item["price"].to_f,
              total: (item["price"].to_f * item["quantity"].to_i)
            }
          end
        }
      end
    }

    render json: response
  end

  # POST /vip_access/send_code_email
  def send_vip_code_email
    emails = params[:emails]
    code_id = params[:code_id]

    unless emails.present? && code_id.present?
      return render json: { error: "Emails and code ID are required" }, status: :bad_request
    end

    # Find VIP code within current restaurant scope
    @vip_code = VipAccessCode.find(code_id)

    # Track failed emails
    failed_emails = []

    # Process each email
    emails.each do |email|
      begin
        VipCodeMailer.vip_code_notification(email, @vip_code, @restaurant).deliver_later
      rescue => e
        failed_emails << { email: email, error: e.message }
      end
    end

    if failed_emails.empty?
      render json: { message: "VIP code emails sent successfully" }
    else
      render json: {
        message: "Some emails failed to send",
        failed: failed_emails
      }, status: :partial_content
    end
  end

  # POST /vip_access/bulk_send_vip_codes
  def bulk_send_vip_codes
    # Extract parameters
    email_list = params[:email_list]
    batch_size = params[:batch_size] || 100

    # Permit and symbolize keys for code options
    code_options = {}
    code_options[:name] = params[:name] if params[:name].present?
    code_options[:prefix] = params[:prefix] if params[:prefix].present?
    code_options[:max_uses] = params[:max_uses].to_i if params[:max_uses].present?

    unless email_list.present?
      return render json: { error: "Email list is required" }, status: :bad_request
    end

    # Pass restaurant_id to background job
    restaurant_id = @restaurant.id

    # Queue background jobs for processing
    email_list.each_slice(batch_size.to_i) do |email_batch|
      SendVipCodesBatchJob.perform_later(email_batch, { restaurant_id: restaurant_id }.merge(code_options))
    end

    render json: {
      message: "VIP code email batches queued for sending",
      total_recipients: email_list.length,
      batch_count: (email_list.length.to_f / batch_size).ceil
    }
  end

  # POST /vip_access/send_existing_vip_codes
  def send_existing_vip_codes
    # Extract parameters
    email_list = params[:email_list]
    code_ids = params[:code_ids]
    batch_size = params[:batch_size] || 100

    unless email_list.present?
      return render json: { error: "Email list is required" }, status: :bad_request
    end

    unless code_ids.present? && code_ids.is_a?(Array)
      return render json: { error: "VIP code IDs are required" }, status: :bad_request
    end

    # Verify that all codes belong to this restaurant
    codes = @restaurant.vip_access_codes.where(id: code_ids)
    if codes.count != code_ids.length
      return render json: { error: "Some VIP codes were not found" }, status: :bad_request
    end

    # Pass restaurant_id to background job
    restaurant_id = @restaurant.id

    # Queue background jobs for processing
    email_list.each_slice(batch_size.to_i) do |email_batch|
      SendVipCodesBatchJob.perform_later(
        email_batch,
        {
          restaurant_id: restaurant_id,
          use_existing_codes: true,
          code_ids: code_ids
        }
      )
    end

    render json: {
      message: "Existing VIP code email batches queued for sending",
      total_recipients: email_list.length,
      batch_count: (email_list.length.to_f / batch_size).ceil
    }
  end

  # GET /vip_access/search_by_email
  def search_by_email
    email = params[:email]

    unless email.present?
      return render json: { error: "Email parameter is required" }, status: :bad_request
    end

    # Use a single efficient query with joins to find all VIP codes that have been sent to the given email
    @codes = VipAccessCode.joins(:vip_code_recipients)
                         .where(restaurant_id: @restaurant.id)
                         .where("vip_code_recipients.email LIKE ?", "%#{email}%")
                         .distinct

    # Apply archived filter unless explicitly requested to include archived
    unless params[:include_archived] == "true"
      @codes = @codes.where(archived: false)
    end

    # Sort by creation date (newest first) by default
    @codes = @codes.order(created_at: :desc)

    # Include recipient information for each code
    codes_with_recipients = @codes.map do |code|
      recipients = code.vip_code_recipients.where("email LIKE ?", "%#{email}%").order(sent_at: :desc)

      code_json = code.as_json
      code_json["recipients"] = recipients.map do |recipient|
        {
          email: recipient.email,
          sent_at: recipient.sent_at
        }
      end

      code_json
    end

    render json: codes_with_recipients
  end

  private

  def set_restaurant
    @restaurant = Restaurant.find(params[:restaurant_id])
  end

  def set_current_restaurant
    @restaurant = current_user.restaurant
  end

  def set_vip_code
    @vip_code = VipAccessCode.find(params[:id])

    # Ensure the VIP code belongs to the current restaurant
    unless @vip_code.restaurant_id == @restaurant&.id
      render json: { error: "VIP code not found" }, status: :not_found
      nil
    end
  end
end
