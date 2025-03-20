module Admin
  class SystemController < ApplicationController
    before_action :authorize_admin
    
    def test_sms
      to = params[:phone]
      body = "This is a test message from #{Rails.application.class.module_parent_name} at #{Time.current.strftime('%H:%M:%S')}"
      
      result = ClicksendClient.send_text_message(
        to: to,
        body: body,
        from: params[:from] || "Test"
      )
      
      if result
        render json: { status: "success", message: "Test SMS queued for delivery" }
      else
        render json: { status: "error", message: "Failed to send test SMS" }, status: :internal_server_error
      end
    end
    
    private
    
    def authorize_admin
      unless current_user&.role.in?(%w[admin super_admin])
        render json: { error: "Unauthorized" }, status: :unauthorized
      end
    end
  end
end
