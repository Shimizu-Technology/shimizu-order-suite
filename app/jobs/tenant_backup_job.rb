# app/jobs/tenant_backup_job.rb
#
# The TenantBackupJob handles tenant data export, import, cloning, and migration
# operations in the background to avoid blocking the web interface.
#
class TenantBackupJob < ApplicationJob
  queue_as :tenant_operations
  
  # Include Sidekiq Status for tracking job progress if available
  begin
    include Sidekiq::Status::Worker if defined?(Sidekiq::Status)
  rescue NameError
    # Sidekiq::Status is not available, continue without it
    Rails.logger.warn "Sidekiq::Status not available, job progress tracking disabled"
    
    # Define a fallback store method if Sidekiq::Status is not available
    def store(status: nil, progress: nil, message: nil, **args)
      # Log the status update instead
      status_info = { status: status, progress: progress, message: message }.merge(args).compact
      Rails.logger.info("Job status update: #{status_info.inspect}")
    end
  end
  
  # Perform the backup operation
  # @param operation [String] the operation to perform (export, import, clone, migrate)
  # @param args [Hash] operation-specific arguments
  def perform(operation, **args)
    # Set initial status
    store(status: 'running', progress: 0, message: "Starting #{operation} operation")
    
    case operation
    when 'export'
      perform_export(args)
    when 'import'
      perform_import(args)
    when 'clone'
      perform_clone(args)
    when 'migrate'
      perform_migrate(args)
    else
      store(status: 'failed', message: "Unknown operation: #{operation}")
      raise ArgumentError, "Unknown operation: #{operation}"
    end
  end
  
  private
  
  # Perform tenant export
  # @param args [Hash] export arguments
  def perform_export(args)
    # Validate arguments
    restaurant_id = args[:restaurant_id]
    raise ArgumentError, "Restaurant ID is required" unless restaurant_id.present?
    
    # Find the restaurant
    restaurant = Restaurant.find_by(id: restaurant_id)
    raise ArgumentError, "Restaurant not found" unless restaurant
    
    # Update status
    store(progress: 10, message: "Exporting data for #{restaurant.name}")
    
    # Perform the export
    export_path = TenantBackupService.export_tenant(
      restaurant,
      user_id: args[:user_id],
      include_empty_tables: args[:include_empty_tables]
    )
    
    # Update status
    store(
      status: 'complete',
      progress: 100,
      message: "Export completed for #{restaurant.name}",
      result: { export_path: export_path }
    )
    
    # Return the export path
    export_path
  rescue => e
    # Log the error
    Rails.logger.error("Error in TenantBackupJob#perform_export: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    
    # Update status
    store(status: 'failed', message: "Export failed: #{e.message}")
    
    # Re-raise the error
    raise
  end
  
  # Perform tenant import
  # @param args [Hash] import arguments
  def perform_import(args)
    # Validate arguments
    backup_id = args[:backup_id]
    raise ArgumentError, "Backup ID is required" unless backup_id.present?
    
    # Find the backup file
    backup_file = find_backup_file(backup_id)
    raise ArgumentError, "Backup not found" unless backup_file
    
    # Update status
    store(progress: 10, message: "Validating backup")
    
    # Validate the backup
    TenantBackupService.validate_backup(backup_file[:path])
    
    # Update status
    store(progress: 20, message: "Preparing to import data")
    
    # Determine import options
    import_options = {
      user_id: args[:user_id],
      clear_existing_data: args[:clear_existing_data] || false,
      update_existing: args[:update_existing] || false,
      activate_restaurant: args[:activate_restaurant] || false
    }
    
    # If a target restaurant is specified, find it
    if args[:target_restaurant_id].present?
      target_restaurant = Restaurant.find_by(id: args[:target_restaurant_id])
      raise ArgumentError, "Target restaurant not found" unless target_restaurant
      
      import_options[:target_restaurant] = target_restaurant
      import_options[:skip_restaurant_creation] = true
      
      # Update status
      store(progress: 30, message: "Importing data to #{target_restaurant.name}")
    elsif args[:new_restaurant_name].present?
      # Create a new restaurant with the specified name
      import_options[:skip_restaurant_creation] = false
      
      # Update status
      store(progress: 30, message: "Importing data to new restaurant: #{args[:new_restaurant_name]}")
    else
      # Use the restaurant from the backup
      import_options[:skip_restaurant_creation] = false
      
      # Update status
      store(progress: 30, message: "Importing data to restaurant from backup")
    end
    
    # Perform the import
    restaurant = TenantBackupService.import_tenant(backup_file[:path], import_options)
    
    # Update status
    store(
      status: 'complete',
      progress: 100,
      message: "Import completed for #{restaurant.name}",
      result: { restaurant_id: restaurant.id, restaurant_name: restaurant.name }
    )
    
    # Return the restaurant
    restaurant
  rescue => e
    # Log the error
    Rails.logger.error("Error in TenantBackupJob#perform_import: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    
    # Update status
    store(status: 'failed', message: "Import failed: #{e.message}")
    
    # Re-raise the error
    raise
  end
  
  # Perform tenant cloning
  # @param args [Hash] clone arguments
  def perform_clone(args)
    # Validate arguments
    source_restaurant_id = args[:source_restaurant_id]
    new_restaurant_name = args[:new_restaurant_name]
    
    raise ArgumentError, "Source restaurant ID is required" unless source_restaurant_id.present?
    raise ArgumentError, "New restaurant name is required" unless new_restaurant_name.present?
    
    # Find the source restaurant
    source_restaurant = Restaurant.find_by(id: source_restaurant_id)
    raise ArgumentError, "Source restaurant not found" unless source_restaurant
    
    # Update status
    store(progress: 10, message: "Preparing to clone #{source_restaurant.name}")
    
    # Determine clone options
    clone_options = {
      user_id: args[:user_id],
      active: args[:activate_restaurant] || false
    }
    
    # Update status
    store(progress: 30, message: "Cloning data to #{new_restaurant_name}")
    
    # Perform the clone
    new_restaurant = TenantBackupService.clone_tenant(
      source_restaurant,
      new_restaurant_name,
      clone_options
    )
    
    # Update status
    store(
      status: 'complete',
      progress: 100,
      message: "Clone completed for #{new_restaurant.name}",
      result: { restaurant_id: new_restaurant.id, restaurant_name: new_restaurant.name }
    )
    
    # Return the new restaurant
    new_restaurant
  rescue => e
    # Log the error
    Rails.logger.error("Error in TenantBackupJob#perform_clone: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    
    # Update status
    store(status: 'failed', message: "Clone failed: #{e.message}")
    
    # Re-raise the error
    raise
  end
  
  # Perform tenant migration
  # @param args [Hash] migration arguments
  def perform_migrate(args)
    # Validate arguments
    backup_id = args[:backup_id]
    target_environment = args[:target_environment]
    
    raise ArgumentError, "Backup ID is required" unless backup_id.present?
    raise ArgumentError, "Target environment is required" unless target_environment.present?
    
    # Find the backup file
    backup_file = find_backup_file(backup_id)
    raise ArgumentError, "Backup not found" unless backup_file
    
    # Update status
    store(progress: 10, message: "Validating backup")
    
    # Validate the backup
    TenantBackupService.validate_backup(backup_file[:path])
    
    # Update status
    store(progress: 30, message: "Migrating to #{target_environment}")
    
    # Perform the migration
    result = TenantBackupService.migrate_tenant(
      backup_file[:path],
      target_environment,
      user_id: args[:user_id]
    )
    
    if result
      # Update status
      store(
        status: 'complete',
        progress: 100,
        message: "Migration to #{target_environment} completed successfully"
      )
    else
      # Update status
      store(
        status: 'failed',
        progress: 100,
        message: "Migration to #{target_environment} failed"
      )
      
      raise "Migration to #{target_environment} failed"
    end
    
    # Return the result
    result
  rescue => e
    # Log the error
    Rails.logger.error("Error in TenantBackupJob#perform_migrate: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    
    # Update status
    store(status: 'failed', message: "Migration failed: #{e.message}")
    
    # Re-raise the error
    raise
  end
  
  # Find a backup file by ID
  # @param backup_id [String] the backup ID
  # @return [Hash, nil] the backup file information or nil if not found
  def find_backup_file(backup_id)
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
    end.find { |backup| backup[:id] == backup_id }
  end
end
