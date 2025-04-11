# app/services/waitlist_entry_service.rb
class WaitlistEntryService < TenantScopedService
  attr_accessor :current_user

  # List all waitlist entries for the current restaurant
  def list_entries(params = {})
    entries = scope_query(WaitlistEntry)
    
    # Apply filters if provided
    if params[:status].present?
      entries = entries.where(status: params[:status])
    end
    
    if params[:date].present?
      date = Date.parse(params[:date])
      entries = entries.where(
        "created_at >= ? AND created_at < ?", 
        date.beginning_of_day, 
        date.end_of_day
      )
    end
    
    if params[:customer_name].present?
      entries = entries.where(
        "customer_name ILIKE ?", 
        "%#{params[:customer_name]}%"
      )
    end
    
    if params[:phone].present?
      entries = entries.where(
        "phone ILIKE ?", 
        "%#{params[:phone]}%"
      )
    end
    
    # Order by created_at (most recent first)
    entries = entries.order(created_at: :desc)
    
    # Paginate if requested
    if params[:page].present? && params[:per_page].present?
      page = params[:page].to_i
      per_page = params[:per_page].to_i
      entries = entries.page(page).per(per_page)
    end
    
    { success: true, entries: entries }
  rescue => e
    { success: false, errors: ["Failed to list waitlist entries: #{e.message}"], status: :internal_server_error }
  end

  # Find a specific waitlist entry
  def find_entry(id)
    entry = scope_query(WaitlistEntry).find_by(id: id)
    
    if entry
      { success: true, entry: entry }
    else
      { success: false, errors: ["Waitlist entry not found"], status: :not_found }
    end
  rescue => e
    { success: false, errors: ["Failed to find waitlist entry: #{e.message}"], status: :internal_server_error }
  end

  # Create a new waitlist entry
  def create_entry(params)
    entry = WaitlistEntry.new(params)
    entry.restaurant = current_restaurant
    
    if entry.save
      { success: true, entry: entry }
    else
      { success: false, errors: entry.errors.full_messages, status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to create waitlist entry: #{e.message}"], status: :internal_server_error }
  end

  # Update an existing waitlist entry
  def update_entry(id, params)
    entry = scope_query(WaitlistEntry).find_by(id: id)
    
    unless entry
      return { success: false, errors: ["Waitlist entry not found"], status: :not_found }
    end
    
    if entry.update(params)
      { success: true, entry: entry }
    else
      { success: false, errors: entry.errors.full_messages, status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to update waitlist entry: #{e.message}"], status: :internal_server_error }
  end

  # Delete a waitlist entry
  def delete_entry(id)
    entry = scope_query(WaitlistEntry).find_by(id: id)
    
    unless entry
      return { success: false, errors: ["Waitlist entry not found"], status: :not_found }
    end
    
    if entry.destroy
      { success: true }
    else
      { success: false, errors: ["Failed to delete waitlist entry"], status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to delete waitlist entry: #{e.message}"], status: :internal_server_error }
  end

  # Change the status of a waitlist entry
  def change_entry_status(id, status)
    entry = scope_query(WaitlistEntry).find_by(id: id)
    
    unless entry
      return { success: false, errors: ["Waitlist entry not found"], status: :not_found }
    end
    
    if entry.update(status: status)
      { success: true, entry: entry }
    else
      { success: false, errors: entry.errors.full_messages, status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to change waitlist entry status: #{e.message}"], status: :internal_server_error }
  end

  # Notify a customer that their table is ready
  def notify_customer(id, notification_type = "sms")
    entry = scope_query(WaitlistEntry).find_by(id: id)
    
    unless entry
      return { success: false, errors: ["Waitlist entry not found"], status: :not_found }
    end
    
    case notification_type
    when "sms"
      if entry.phone.blank?
        return { success: false, errors: ["No phone number available for SMS notification"], status: :unprocessable_entity }
      end
      
      # Send SMS notification
      message = "Hello #{entry.customer_name}, your table at #{current_restaurant.name} is now ready! Please check in with our host."
      
      # Use your SMS service here
      # Example: SmsService.send_message(entry.phone, message)
      
      # Update the entry to record the notification
      entry.update(
        last_notified_at: Time.current,
        notification_count: entry.notification_count.to_i + 1
      )
      
      { success: true, entry: entry }
    when "email"
      if entry.email.blank?
        return { success: false, errors: ["No email available for email notification"], status: :unprocessable_entity }
      end
      
      # Send email notification
      # Example: WaitlistMailer.table_ready(entry).deliver_later
      
      # Update the entry to record the notification
      entry.update(
        last_notified_at: Time.current,
        notification_count: entry.notification_count.to_i + 1
      )
      
      { success: true, entry: entry }
    else
      { success: false, errors: ["Unsupported notification type: #{notification_type}"], status: :unprocessable_entity }
    end
  rescue => e
    { success: false, errors: ["Failed to notify customer: #{e.message}"], status: :internal_server_error }
  end
end
