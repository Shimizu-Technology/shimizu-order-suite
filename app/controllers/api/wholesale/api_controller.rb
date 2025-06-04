# app/controllers/api/wholesale/api_controller.rb

module Api
  module Wholesale
    class ApiController < Api::ApiController
      # Common functionality for all wholesale API controllers
      # Authorization is handled in each controller
      before_action :ensure_restaurant_context
      
      private
      
      def ensure_restaurant_context
        unless current_restaurant.present?
          render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
        end
      end
    end
  end
end
