# app/services/promo_code_service.rb
class PromoCodeService
  attr_reader :current_restaurant, :analytics
  
  def initialize(current_restaurant = nil, analytics_service = nil)
    @current_restaurant = current_restaurant
    @analytics = analytics_service || AnalyticsService.new
  end
  
  # List all promo codes based on user role
  def list_promo_codes(current_user)
    begin
      # Admin users can see all promo codes for their restaurant
      if current_user&.role.in?(%w[admin super_admin])
        if current_user.role == "super_admin"
          # Super admins can see all promo codes across restaurants
          promo_codes = PromoCode.all
        else
          # Regular admins can only see promo codes for their restaurant
          promo_codes = PromoCode.where(restaurant_id: current_restaurant.id)
        end
      else
        # Regular users can only see active promo codes for their restaurant
        promo_codes = PromoCode.where(restaurant_id: current_restaurant.id)
                              .where("valid_until > ? OR valid_until IS NULL", Time.now)
      end
      
      # Track analytics
      analytics.track("promo_codes.listed", {
        restaurant_id: current_restaurant&.id,
        user_id: current_user&.id,
        count: promo_codes.count,
        role: current_user&.role
      })
      
      { success: true, promo_codes: promo_codes }
    rescue => e
      { success: false, errors: ["Failed to retrieve promo codes: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Get a specific promo code by ID or code
  def get_promo_code(id_or_code)
    begin
      # Try to find by code first, then by ID
      promo_code = PromoCode.find_by(code: id_or_code) || 
                   PromoCode.find_by(id: id_or_code)
      
      unless promo_code
        return { success: false, errors: ["Promo code not found"], status: :not_found }
      end
      
      # If current_restaurant is set, ensure the promo code belongs to this restaurant
      if current_restaurant && promo_code.restaurant_id != current_restaurant.id
        return { success: false, errors: ["Promo code not found"], status: :not_found }
      end
      
      # Track analytics
      analytics.track("promo_code.viewed", {
        restaurant_id: current_restaurant&.id,
        promo_code_id: promo_code.id,
        promo_code: promo_code.code
      })
      
      { success: true, promo_code: promo_code }
    rescue => e
      { success: false, errors: ["Failed to retrieve promo code: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Create a new promo code (admin only)
  def create_promo_code(promo_code_params, current_user)
    begin
      # Only admin users can create promo codes
      unless current_user && current_user.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      # Set the restaurant_id to the current restaurant unless specified by a super_admin
      unless current_user.role == "super_admin" && promo_code_params[:restaurant_id].present?
        promo_code_params[:restaurant_id] = current_restaurant.id
      end
      
      promo_code = PromoCode.new(promo_code_params)
      
      if promo_code.save
        # Track analytics
        analytics.track("promo_code.created", {
          restaurant_id: promo_code.restaurant_id,
          user_id: current_user.id,
          promo_code_id: promo_code.id,
          promo_code: promo_code.code
        })
        
        { success: true, promo_code: promo_code, status: :created }
      else
        { success: false, errors: promo_code.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to create promo code: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Update an existing promo code (admin only)
  def update_promo_code(id, promo_code_params, current_user)
    begin
      # Only admin users can update promo codes
      unless current_user && current_user.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      promo_code = PromoCode.find_by(id: id)
      
      unless promo_code
        return { success: false, errors: ["Promo code not found"], status: :not_found }
      end
      
      # Ensure the promo code belongs to the current restaurant unless user is super_admin
      unless current_user.role == "super_admin"
        if promo_code.restaurant_id != current_restaurant.id
          return { success: false, errors: ["Promo code not found"], status: :not_found }
        end
      end
      
      # Don't allow changing restaurant_id unless user is super_admin
      if promo_code_params[:restaurant_id].present? && 
         promo_code_params[:restaurant_id] != promo_code.restaurant_id &&
         current_user.role != "super_admin"
        return { success: false, errors: ["Cannot change restaurant for promo code"], status: :forbidden }
      end
      
      if promo_code.update(promo_code_params)
        # Track analytics
        analytics.track("promo_code.updated", {
          restaurant_id: promo_code.restaurant_id,
          user_id: current_user.id,
          promo_code_id: promo_code.id,
          promo_code: promo_code.code
        })
        
        { success: true, promo_code: promo_code }
      else
        { success: false, errors: promo_code.errors.full_messages, status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to update promo code: #{e.message}"], status: :internal_server_error }
    end
  end
  
  # Delete a promo code (admin only)
  def delete_promo_code(id, current_user)
    begin
      # Only admin users can delete promo codes
      unless current_user && current_user.role.in?(%w[admin super_admin])
        return { success: false, errors: ["Forbidden"], status: :forbidden }
      end
      
      promo_code = PromoCode.find_by(id: id)
      
      unless promo_code
        return { success: false, errors: ["Promo code not found"], status: :not_found }
      end
      
      # Ensure the promo code belongs to the current restaurant unless user is super_admin
      unless current_user.role == "super_admin"
        if promo_code.restaurant_id != current_restaurant.id
          return { success: false, errors: ["Promo code not found"], status: :not_found }
        end
      end
      
      # Store promo code details for analytics before deletion
      promo_code_details = {
        id: promo_code.id,
        code: promo_code.code,
        restaurant_id: promo_code.restaurant_id
      }
      
      if promo_code.destroy
        # Track analytics
        analytics.track("promo_code.deleted", {
          restaurant_id: promo_code_details[:restaurant_id],
          user_id: current_user.id,
          promo_code_id: promo_code_details[:id],
          promo_code: promo_code_details[:code]
        })
        
        { success: true }
      else
        { success: false, errors: ["Failed to delete promo code"], status: :unprocessable_entity }
      end
    rescue => e
      { success: false, errors: ["Failed to delete promo code: #{e.message}"], status: :internal_server_error }
    end
  end
end
