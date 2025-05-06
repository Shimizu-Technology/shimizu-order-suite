# app/controllers/api/v1/api_controller.rb
module Api
  module V1
    class ApiController < ApplicationController
      # Handle record not found errors
      rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
      
      private
      
      def record_not_found(exception)
        render json: { error: exception.message }, status: :not_found
      end
    end
  end
end
