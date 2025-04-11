# app/controllers/admin/tenant_backup_controller.rb
#
# The Admin::TenantBackupController provides an interface for administrators
# to export, import, and manage tenant data backups for disaster recovery
# and migration purposes.
#
class Admin::TenantBackupController < ApplicationController
  before_action :authorize_request
  before_action :authorize_super_admin, except: [:export_tenant, :backup_status]
  before_action :authorize_admin, only: [:export_tenant, :backup_status]
  before_action :set_restaurant, only: [:export_tenant, :backup_status]
  
  # GET /admin/tenant_backup/backups
  # Lists all available backups
  def backups
    @backups = list_backup_files
    
    render json: { backups: @backups }
  end
  
  # POST /admin/tenant_backup/export_tenant/:id
  # Exports a tenant's data to a backup file
  def export_tenant
    # Only allow super admins to export any tenant
    # Regular admins can only export their own tenant
    unless current_user.super_admin? || current_user.restaurant_id == @restaurant.id
      return render json: { error: "You don't have permission to export this tenant" }, status: :forbidden
    end
    
    # Start the export in a background job
    job = TenantBackupJob.perform_later(
      'export',
      restaurant_id: @restaurant.id,
      user_id: current_user.id,
      include_empty_tables: params[:include_empty_tables] || false
    )
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'export',
      'Restaurant',
      @restaurant.id,
      request.remote_ip,
      { job_id: job.job_id }
    )
    
    render json: {
      message: "Export started for #{@restaurant.name}",
      job_id: job.job_id
    }
  end
  
  # POST /admin/tenant_backup/import_tenant
  # Imports a tenant from a backup file
  def import_tenant
    # Validate parameters
    unless params[:backup_id].present?
      return render json: { error: "Backup ID is required" }, status: :bad_request
    end
    
    # Find the backup file
    backup_file = find_backup_file(params[:backup_id])
    unless backup_file
      return render json: { error: "Backup not found" }, status: :not_found
    end
    
    # Start the import in a background job
    job = TenantBackupJob.perform_later(
      'import',
      backup_id: params[:backup_id],
      user_id: current_user.id,
      target_restaurant_id: params[:target_restaurant_id],
      new_restaurant_name: params[:new_restaurant_name],
      clear_existing_data: params[:clear_existing_data] || false,
      update_existing: params[:update_existing] || false,
      activate_restaurant: params[:activate_restaurant] || false
    )
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'import',
      'Restaurant',
      params[:target_restaurant_id],
      request.remote_ip,
      { job_id: job.job_id, backup_id: params[:backup_id] }
    )
    
    render json: {
      message: "Import started for backup #{params[:backup_id]}",
      job_id: job.job_id
    }
  end
  
  # POST /admin/tenant_backup/clone_tenant
  # Clones a tenant to a new restaurant
  def clone_tenant
    # Validate parameters
    unless params[:source_restaurant_id].present? && params[:new_restaurant_name].present?
      return render json: { error: "Source restaurant ID and new restaurant name are required" }, status: :bad_request
    end
    
    # Find the source restaurant
    source_restaurant = Restaurant.find_by(id: params[:source_restaurant_id])
    unless source_restaurant
      return render json: { error: "Source restaurant not found" }, status: :not_found
    end
    
    # Start the clone in a background job
    job = TenantBackupJob.perform_later(
      'clone',
      source_restaurant_id: params[:source_restaurant_id],
      new_restaurant_name: params[:new_restaurant_name],
      user_id: current_user.id,
      activate_restaurant: params[:activate_restaurant] || false
    )
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'clone',
      'Restaurant',
      source_restaurant.id,
      request.remote_ip,
      { job_id: job.job_id, new_name: params[:new_restaurant_name] }
    )
    
    render json: {
      message: "Clone started from #{source_restaurant.name} to #{params[:new_restaurant_name]}",
      job_id: job.job_id
    }
  end
  
  # POST /admin/tenant_backup/migrate_tenant
  # Migrates a tenant to another environment
  def migrate_tenant
    # Validate parameters
    unless params[:backup_id].present? && params[:target_environment].present?
      return render json: { error: "Backup ID and target environment are required" }, status: :bad_request
    end
    
    # Find the backup file
    backup_file = find_backup_file(params[:backup_id])
    unless backup_file
      return render json: { error: "Backup not found" }, status: :not_found
    end
    
    # Validate the target environment
    valid_environments = ['staging', 'production']
    unless valid_environments.include?(params[:target_environment])
      return render json: { error: "Invalid target environment" }, status: :bad_request
    end
    
    # Start the migration in a background job
    job = TenantBackupJob.perform_later(
      'migrate',
      backup_id: params[:backup_id],
      target_environment: params[:target_environment],
      user_id: current_user.id
    )
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'migrate',
      'Backup',
      params[:backup_id],
      request.remote_ip,
      { job_id: job.job_id, target_environment: params[:target_environment] }
    )
    
    render json: {
      message: "Migration started for backup #{params[:backup_id]} to #{params[:target_environment]}",
      job_id: job.job_id
    }
  end
  
  # DELETE /admin/tenant_backup/delete_backup/:id
  # Deletes a backup file
  def delete_backup
    # Validate parameters
    unless params[:id].present?
      return render json: { error: "Backup ID is required" }, status: :bad_request
    end
    
    # Find the backup file
    backup_file = find_backup_file(params[:id])
    unless backup_file
      return render json: { error: "Backup not found" }, status: :not_found
    end
    
    # Delete the backup file
    File.delete(backup_file[:path]) if File.exist?(backup_file[:path])
    
    # Log the action
    AuditLog.log_data_modification(
      current_user,
      'delete',
      'Backup',
      params[:id],
      request.remote_ip,
      { backup_id: params[:id] }
    )
    
    render json: {
      message: "Backup #{params[:id]} deleted successfully"
    }
  end
  
  # GET /admin/tenant_backup/validate_backup/:id
  # Validates a backup file
  def validate_backup
    # Validate parameters
    unless params[:id].present?
      return render json: { error: "Backup ID is required" }, status: :bad_request
    end
    
    # Find the backup file
    backup_file = find_backup_file(params[:id])
    unless backup_file
      return render json: { error: "Backup not found" }, status: :not_found
    end
    
    begin
      # Validate the backup
      TenantBackupService.validate_backup(backup_file[:path])
      
      render json: {
        message: "Backup #{params[:id]} is valid",
        valid: true
      }
    rescue ArgumentError => e
      render json: {
        message: e.message,
        valid: false
      }, status: :unprocessable_entity
    end
  end
  
  # GET /admin/tenant_backup/backup_status/:job_id
  # Checks the status of a backup job
  def backup_status
    # Validate parameters
    unless params[:job_id].present?
      return render json: { error: "Job ID is required" }, status: :bad_request
    end
    
    # Find the job
    job_status = Sidekiq::Status.get_all(params[:job_id])
    
    if job_status.empty?
      render json: { error: "Job not found" }, status: :not_found
    else
      render json: {
        status: job_status['status'],
        progress: job_status['progress'],
        message: job_status['message']
      }
    end
  end
  
  private
  
  def set_restaurant
    @restaurant = if params[:id].present?
                    Restaurant.find(params[:id])
                  else
                    current_restaurant
                  end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Restaurant not found" }, status: :not_found
  end
  
  def authorize_admin
    unless current_user&.admin? || current_user&.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
  
  def authorize_super_admin
    unless current_user&.super_admin?
      render json: { error: "Unauthorized" }, status: :forbidden
    end
  end
  
  def list_backup_files
    # Get all backup files in the exports directory
    export_dir = Rails.root.join('tmp', 'exports')
    FileUtils.mkdir_p(export_dir)
    
    # Find all zip files
    backup_files = Dir.glob(File.join(export_dir, '*.zip'))
    
    # Parse the backup files
    backup_files.map do |file_path|
      file_name = File.basename(file_path)
      
      # Extract the export ID from the filename
      if file_name =~ /tenant_export_(\d+)_(\d{14})\.zip/
        restaurant_id = $1
        timestamp = $2
        
        # Find the restaurant
        restaurant = Restaurant.find_by(id: restaurant_id)
        
        {
          id: File.basename(file_path, '.zip'),
          restaurant_id: restaurant_id.to_i,
          restaurant_name: restaurant&.name || 'Unknown',
          created_at: Time.strptime(timestamp, '%Y%m%d%H%M%S'),
          size: File.size(file_path),
          path: file_path
        }
      else
        # For other backup files
        {
          id: File.basename(file_path, '.zip'),
          created_at: File.mtime(file_path),
          size: File.size(file_path),
          path: file_path
        }
      end
    end.sort_by { |backup| backup[:created_at] }.reverse
  end
  
  def find_backup_file(backup_id)
    list_backup_files.find { |backup| backup[:id] == backup_id }
  end
end
