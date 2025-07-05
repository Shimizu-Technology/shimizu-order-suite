# app/services/vip_access_codes_service.rb
class VipAccessCodesService < TenantScopedService
  attr_reader :analytics
  
  def initialize(current_restaurant = nil, analytics_service = nil)
    super(current_restaurant)
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # Validate a VIP access code
  def validate_code(code, restaurant)
    begin
      if code.blank?
        return { valid: false, message: "VIP code is required", status: :bad_request }
      end

      # Check if the restaurant has VIP-only checkout enabled
      unless restaurant.vip_only_checkout?
        return { valid: true, message: "VIP access not required" }
      end

      # Find the VIP code
      vip_code = restaurant.vip_access_codes.find_by(code: code)

      # Check if the code exists and is available
      if vip_code && vip_code.available?
        # Track analytics
        analytics.track("vip_code.validated", {
          restaurant_id: restaurant.id,
          vip_code_id: vip_code.id,
          vip_code: vip_code.code
        })
        
        { valid: true, message: "Valid VIP code" }
      else
        # Provide a more specific error message if the code exists but has reached its usage limit
        if vip_code && vip_code.max_uses && vip_code.current_uses >= vip_code.max_uses
          { valid: false, message: "This VIP code has reached its maximum usage limit", status: :unauthorized }
        else
          { valid: false, message: "Invalid VIP code", status: :unauthorized }
        end
      end
    rescue => e
      { valid: false, message: "Error validating VIP code: #{e.message}", status: :internal_server_error }
    end
  end
  
  # Get VIP access codes for the current restaurant
  def list_codes(params = {})
    begin
      # Filter by special event if provided
      codes = if params[:special_event_id].present?
        special_event = scope_query(SpecialEvent).find_by(id: params[:special_event_id])
        special_event ? special_event.vip_access_codes : []
      else
        # Otherwise, get all codes for the restaurant
        scope_query(VipAccessCode).all
      end
      
      # By default, don't show archived codes unless explicitly requested
      unless params[:include_archived] == "true"
        codes = codes.where(archived: false)
      end

      # Sort by creation date (newest first) by default
      codes = codes.order(created_at: :desc)
      
      # Track analytics
      analytics.track("vip_codes.listed", {
        restaurant_id: restaurant.id,
        count: codes.count,
        include_archived: params[:include_archived] == "true"
      })
      
      { success: true, codes: codes }
    rescue => e
      { success: false, errors: ["Failed to retrieve VIP codes: #{e.message}"], status: :internal_server_error }
    end
  end

  # Create a new VIP access code or batch of codes
  def create_codes(params, current_user)
    begin
      # Check if the user has permission
      unless current_user.role.in?(%w[admin super_admin]) || current_user.restaurant_id == restaurant.id
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      options = {
        name: params[:name],
        prefix: params[:prefix],
        max_uses: params[:max_uses].present? ? params[:max_uses].to_i : nil
      }

      # Add custom codes if provided
      if params[:custom_codes].present?
        options[:custom_codes] = params[:custom_codes]
      elsif params[:custom_code].present?
        options[:custom_code] = params[:custom_code]
      end

      # Add special event reference if needed
      if params[:special_event_id].present?
        special_event = scope_query(SpecialEvent).find_by(id: params[:special_event_id])
        options[:special_event_id] = special_event.id if special_event
      end

      vip_codes = if params[:batch]
        # Generate multiple individual codes
        count = params[:count].to_i || 1
        VipCodeGenerator.generate_codes(restaurant, count, options)
      else
        # Generate a single group code
        [VipCodeGenerator.generate_group_code(restaurant, options)]
      end
      
      # Track analytics
      analytics.track("vip_codes.created", {
        restaurant_id: restaurant.id,
        user_id: current_user.id,
        count: vip_codes.length,
        batch: params[:batch] || false
      })
      
      { success: true, vip_codes: vip_codes }
    rescue => e
      { success: false, errors: ["Failed to create VIP codes: #{e.message}"], status: :internal_server_error }
    end
  end

  # Update an existing VIP access code
  def update_code(id, vip_code_params)
    begin
      vip_code = scope_query(VipAccessCode).find_by(id: id)
      
      unless vip_code
        return { success: false, errors: ["VIP code not found"], status: :not_found }
      end
      
      if vip_code.update(vip_code_params)
        # Track analytics
        analytics.track("vip_code.updated", {
          restaurant_id: restaurant.id,
          vip_code_id: vip_code.id,
          vip_code: vip_code.code
        })
        
        { success: true, vip_code: vip_code }
      else
        { success: false, errors: vip_code.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update VIP code: #{e.message}"], status: :internal_server_error }
    end
  end

  # Deactivate a VIP access code
  def deactivate_code(id)
    begin
      vip_code = scope_query(VipAccessCode).find_by(id: id)
      
      unless vip_code
        return { success: false, errors: ["VIP code not found"], status: :not_found }
      end
      
      if vip_code.update(is_active: false)
        # Track analytics
        analytics.track("vip_code.deactivated", {
          restaurant_id: restaurant.id,
          vip_code_id: vip_code.id,
          vip_code: vip_code.code
        })
        
        { success: true, message: "VIP code deactivated successfully" }
      else
        { success: false, errors: vip_code.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to deactivate VIP code: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Archive a VIP access code
  def archive_code(id)
    begin
      vip_code = scope_query(VipAccessCode).find_by(id: id)
      
      unless vip_code
        return { success: false, errors: ["VIP code not found"], status: :not_found }
      end
      
      if vip_code.update(archived: true, is_active: false)
        # Track analytics
        analytics.track("vip_code.archived", {
          restaurant_id: restaurant.id,
          vip_code_id: vip_code.id,
          vip_code: vip_code.code
        })
        
        { success: true, message: "VIP code archived successfully" }
      else
        { success: false, errors: vip_code.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to archive VIP code: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get usage information for a VIP code
  def code_usage(id)
    begin
      vip_code = scope_query(VipAccessCode).find_by(id: id)
      
      unless vip_code
        return { success: false, errors: ["VIP code not found"], status: :not_found }
      end
      
      # Get orders that used this VIP code
      orders = vip_code.orders.includes(:user).order(created_at: :desc)
      
      # Get recipients of this VIP code
      recipients = vip_code.vip_code_recipients.order(sent_at: :desc)
      
      # Prepare the response with code details, recipient information, and order information
      response = {
        code: vip_code.as_json,
        usage_count: orders.count,
        recipients: recipients.map do |recipient|
          {
            email: recipient.email,
            sent_at: recipient.sent_at
          }
        end,
        orders: orders.map do |order|
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
      
      # Track analytics
      analytics.track("vip_code.usage_viewed", {
        restaurant_id: restaurant.id,
        vip_code_id: vip_code.id,
        vip_code: vip_code.code,
        usage_count: orders.count,
        recipient_count: recipients.count
      })
      
      { success: true, usage: response }
    rescue => e
      { success: false, errors: ["Failed to get VIP code usage: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Send VIP code email to recipients
  def send_vip_code_email(emails, code_id)
    begin
      unless emails.present? && code_id.present?
        return { success: false, errors: ["Emails and code ID are required"], status: :bad_request }
      end
      
      # Find VIP code within current restaurant scope
      vip_code = scope_query(VipAccessCode).find_by(id: code_id)
      
      unless vip_code
        return { success: false, errors: ["VIP code not found"], status: :not_found }
      end
      
      # Track failed emails
      failed_emails = []
      
      # Process each email
      emails.each do |email|
        begin
          VipCodeMailer.vip_code_notification(email, vip_code, restaurant).deliver_later
          
          # Track recipient
          vip_code.vip_code_recipients.create(email: email, sent_at: Time.now)
        rescue => e
          failed_emails << { email: email, error: e.message }
        end
      end
      
      # Track analytics
      analytics.track("vip_code.emails_sent", {
        restaurant_id: restaurant.id,
        vip_code_id: vip_code.id,
        vip_code: vip_code.code,
        email_count: emails.length,
        failed_count: failed_emails.length
      })
      
      if failed_emails.empty?
        { success: true, message: "VIP code emails sent successfully" }
      else
        { 
          success: false, 
          message: "Some emails failed to send",
          failed: failed_emails,
          status: :partial_content
        }
      end
    rescue => e
      { success: false, errors: ["Failed to send VIP code emails: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Search for VIP codes by recipient email
  def search_by_email(email, params = {})
    begin
      unless email.present?
        return { success: false, errors: ["Email parameter is required"], status: :bad_request }
      end
      
      # Use a single efficient query with joins to find all VIP codes that have been sent to the given email
      codes = VipAccessCode.joins(:vip_code_recipients)
                          .where(restaurant_id: restaurant.id)
                          .where("vip_code_recipients.email LIKE ?", "%#{email}%")
                          .distinct
      
      # Apply archived filter unless explicitly requested to include archived
      unless params[:include_archived] == "true"
        codes = codes.where(archived: false)
      end
      
      # Sort by creation date (newest first) by default
      codes = codes.order(created_at: :desc)
      
      # Include recipient information for each code
      codes_with_recipients = codes.map do |code|
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
      
      # Track analytics
      analytics.track("vip_codes.searched_by_email", {
        restaurant_id: restaurant.id,
        email: email,
        result_count: codes.count
      })
      
      { success: true, codes: codes_with_recipients }
    rescue => e
      { success: false, errors: ["Failed to search VIP codes by email: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Queue bulk sending of VIP codes
  def bulk_send_vip_codes(email_list, params)
    begin
      batch_size = params[:batch_size] || 100
      one_code_per_batch = params[:one_code_per_batch].nil? ? true : params[:one_code_per_batch]
      
      # Permit and symbolize keys for code options
      code_options = {}
      code_options[:name] = params[:name] if params[:name].present?
      code_options[:prefix] = params[:prefix] if params[:prefix].present?
      code_options[:max_uses] = params[:max_uses].to_i if params[:max_uses].present?
      code_options[:one_code_per_batch] = one_code_per_batch
      
      # Add custom codes if provided
      if params[:custom_codes].present?
        code_options[:custom_codes] = params[:custom_codes]
      elsif params[:custom_code].present?
        code_options[:custom_code] = params[:custom_code]
      end
      
      unless email_list.present?
        return { success: false, errors: ["Email list is required"], status: :bad_request }
      end
      
      # Pass restaurant_id to background job
      restaurant_id = restaurant.id
      
      # Queue background jobs for processing
      email_list.each_slice(batch_size.to_i) do |email_batch|
        SendVipCodesBatchJob.perform_later(email_batch, { restaurant_id: restaurant_id }.merge(code_options))
      end
      
      # Track analytics
      analytics.track("vip_codes.bulk_send_queued", {
        restaurant_id: restaurant.id,
        total_recipients: email_list.length,
        batch_count: (email_list.length.to_f / batch_size).ceil,
        one_code_per_batch: one_code_per_batch
      })
      
      { 
        success: true,
        message: "VIP code email batches queued for sending",
        total_recipients: email_list.length,
        batch_count: (email_list.length.to_f / batch_size).ceil,
        one_code_per_batch: one_code_per_batch
      }
    rescue => e
      { success: false, errors: ["Failed to queue VIP code emails: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Queue sending of existing VIP codes
  def send_existing_vip_codes(email_list, code_ids, params)
    begin
      batch_size = params[:batch_size] || 100
      
      unless email_list.present?
        return { success: false, errors: ["Email list is required"], status: :bad_request }
      end
      
      unless code_ids.present? && code_ids.is_a?(Array)
        return { success: false, errors: ["VIP code IDs are required"], status: :bad_request }
      end
      
      # Verify that all codes belong to this restaurant
      codes = scope_query(VipAccessCode).where(id: code_ids)
      if codes.count != code_ids.length
        return { success: false, errors: ["Some VIP codes were not found"], status: :bad_request }
      end
      
      # Pass restaurant_id to background job
      restaurant_id = restaurant.id
      
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
      
      # Track analytics
      analytics.track("vip_codes.existing_send_queued", {
        restaurant_id: restaurant.id,
        total_recipients: email_list.length,
        batch_count: (email_list.length.to_f / batch_size).ceil,
        code_count: code_ids.length
      })
      
      { 
        success: true,
        message: "Existing VIP code email batches queued for sending",
        total_recipients: email_list.length,
        batch_count: (email_list.length.to_f / batch_size).ceil
      }
    rescue => e
      { success: false, errors: ["Failed to queue existing VIP code emails: #{e.message}"], status: :internal_server_error }
    end
  end
end
