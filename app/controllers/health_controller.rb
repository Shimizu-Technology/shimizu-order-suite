class HealthController < ApplicationController
  def check
    inconsistencies = []
    
    # Check orders table
    expected_order_columns = ['id', 'restaurant_id', 'user_id', 'items', 'status', 'total', 
                       'promo_code', 'special_instructions', 'estimated_pickup_time', 
                       'created_at', 'updated_at', 'contact_name', 'contact_phone', 
                       'contact_email', 'payment_method', 'transaction_id', 
                       'payment_status', 'payment_amount', 'vip_code', 'vip_access_code_id']
    
    actual_columns = Order.column_names
    missing_from_order = expected_order_columns - actual_columns
    
    if missing_from_order.any?
      inconsistencies << "Orders table missing: #{missing_from_order.join(', ')}"
    end
    
    # Add checks for other critical tables as needed
    
    if inconsistencies.any?
      render json: { status: 'error', schema_issues: inconsistencies }, status: :service_unavailable
    else
      render json: { status: 'ok', message: 'Schema integrity verified' }
    end
  end
end
