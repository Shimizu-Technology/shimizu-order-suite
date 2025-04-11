# app/controllers/admin/reports_controller.rb
module Admin
  class ReportsController < ApplicationController
    include TenantIsolation
    
    before_action :authorize_request
    before_action :ensure_admin_or_staff
    before_action :ensure_tenant_context

    # GET /admin/reports/menu_items
    def menu_items
      start_date = params[:start_date]
      end_date = params[:end_date]
      
      # Use the ReportService to get menu items report with tenant isolation
      report_data = report_service.menu_items_report(start_date, end_date)
      
      render json: report_data
    end

    # GET /admin/reports/payment_methods
    def payment_methods
      start_date = params[:start_date]
      end_date = params[:end_date]
      
      # Use the ReportService to get payment methods report with tenant isolation
      report_data = report_service.payment_methods_report(start_date, end_date)
      
      render json: report_data
    end

    # GET /admin/reports/vip_customers
    def vip_customers
      start_date = params[:start_date]
      end_date = params[:end_date]
      
      # Use the ReportService to get VIP customers report with tenant isolation
      report_data = report_service.vip_customers_report(start_date, end_date)
      
      render json: report_data
    end

    private

    def ensure_admin_or_staff
      # Check for super_admin, admin, or staff roles
      unless current_user&.super_admin? || current_user&.admin? || current_user&.staff?
        render json: { error: 'Unauthorized' }, status: :unauthorized
      end
    end
    
    def report_service
      @report_service ||= ReportService.new(current_restaurant)
    end
    
    def ensure_tenant_context
      unless current_restaurant.present?
        render json: { error: 'Restaurant context is required' }, status: :unprocessable_entity
      end
    end
  end
end
