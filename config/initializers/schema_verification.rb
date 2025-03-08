# config/initializers/schema_verification.rb
if Rails.env.production?
  Rails.application.config.after_initialize do
    begin
      Rails.logger.info "Verifying database schema integrity..."
      
      # Orders table verification
      missing_columns = []
      expected_order_columns = ['id', 'restaurant_id', 'user_id', 'items', 'status', 'total', 
                         'promo_code', 'special_instructions', 'estimated_pickup_time', 
                         'created_at', 'updated_at', 'contact_name', 'contact_phone', 
                         'contact_email', 'payment_method', 'transaction_id', 
                         'payment_status', 'payment_amount', 'vip_code', 'vip_access_code_id']
      
      actual_columns = Order.column_names
      missing_from_order = expected_order_columns - actual_columns
      
      if missing_from_order.any?
        missing_columns << "Orders table missing: #{missing_from_order.join(', ')}"
      end
      
      # Add similar checks for other critical tables here
      
      if missing_columns.any?
        message = "SCHEMA INTEGRITY ERROR: #{missing_columns.join('; ')}"
        Rails.logger.error message
        
        # Optional: Send an alert via email or other notification system
        # AdminMailer.schema_error_alert(message).deliver_now if defined?(AdminMailer)
      else
        Rails.logger.info "Database schema integrity verified successfully"
      end
    rescue => e
      Rails.logger.error "Error during schema verification: #{e.message}"
    end
  end
end
