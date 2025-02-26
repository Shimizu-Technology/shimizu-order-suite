# app/controllers/concerns/restaurant_scope.rb
module RestaurantScope
  extend ActiveSupport::Concern
  
  included do
    before_action :set_restaurant_scope
  end
  
  private
  
  def set_restaurant_scope
    # For super_admin users who can access multiple restaurants
    if current_user&.role == 'super_admin'
      # Allow super_admin to specify which restaurant to work with
      @current_restaurant = if params[:restaurant_id].present?
                             Restaurant.find_by(id: params[:restaurant_id])
                           else
                             nil # Super admins can access global endpoints without restaurant context
                           end
    else
      # For regular users, always use their associated restaurant
      @current_restaurant = current_user&.restaurant
      
      # If no restaurant is associated and this isn't a public endpoint,
      # return an error
      unless @current_restaurant || public_endpoint?
        render json: { error: "Restaurant context required" }, status: :unprocessable_entity
        return
      end
    end
    
    # Make current_restaurant available to models for default scoping
    # This requires adding thread_mattr_accessor to ApplicationRecord
    ActiveRecord::Base.current_restaurant = @current_restaurant if ActiveRecord::Base.respond_to?(:current_restaurant=)
  end
  
  # Override this method in controllers that have public endpoints
  def public_endpoint?
    false
  end
end
