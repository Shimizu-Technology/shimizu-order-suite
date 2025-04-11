# lib/tasks/tenant_backup.rake
#
# Rake tasks for automating tenant backups and disaster recovery operations.
# These tasks can be scheduled using cron or another scheduler to run regularly.
#
namespace :tenant do
  namespace :backup do
    desc "Backup all tenants"
    task :all => :environment do
      puts "Starting backup of all tenants at #{Time.current}"
      
      # Get all active restaurants
      restaurants = Restaurant.where(active: true)
      
      puts "Found #{restaurants.count} active restaurants to backup"
      
      # Backup each restaurant
      restaurants.each do |restaurant|
        puts "Backing up #{restaurant.name} (ID: #{restaurant.id})"
        
        begin
          # Export the tenant data
          export_path = TenantBackupService.export_tenant(restaurant)
          puts "  Backup completed: #{export_path}"
        rescue => e
          puts "  ERROR: Backup failed for #{restaurant.name}: #{e.message}"
          puts e.backtrace.join("\n")
        end
      end
      
      puts "All tenant backups completed at #{Time.current}"
    end
    
    desc "Backup a specific tenant by ID"
    task :tenant, [:restaurant_id] => :environment do |t, args|
      restaurant_id = args[:restaurant_id]
      
      if restaurant_id.blank?
        puts "ERROR: Restaurant ID is required"
        puts "Usage: rake tenant:backup:tenant[restaurant_id]"
        exit 1
      end
      
      # Find the restaurant
      restaurant = Restaurant.find_by(id: restaurant_id)
      
      unless restaurant
        puts "ERROR: Restaurant with ID #{restaurant_id} not found"
        exit 1
      end
      
      puts "Starting backup of #{restaurant.name} (ID: #{restaurant.id}) at #{Time.current}"
      
      begin
        # Export the tenant data
        export_path = TenantBackupService.export_tenant(restaurant)
        puts "Backup completed: #{export_path}"
      rescue => e
        puts "ERROR: Backup failed: #{e.message}"
        puts e.backtrace.join("\n")
        exit 1
      end
    end
    
    desc "Clean up old backups, keeping only the specified number of recent backups per tenant"
    task :cleanup, [:keep_count] => :environment do |t, args|
      keep_count = (args[:keep_count] || 5).to_i
      
      puts "Starting backup cleanup, keeping #{keep_count} most recent backups per tenant"
      
      # Get all backup files
      export_dir = Rails.root.join('tmp', 'exports')
      FileUtils.mkdir_p(export_dir)
      
      # Group backups by restaurant
      backups_by_restaurant = {}
      
      Dir.glob(File.join(export_dir, '*.zip')).each do |file_path|
        file_name = File.basename(file_path)
        
        # Extract the restaurant ID from the filename
        if file_name =~ /tenant_export_(\d+)_(\d{14})\.zip/
          restaurant_id = $1
          timestamp = $2
          
          backups_by_restaurant[restaurant_id] ||= []
          backups_by_restaurant[restaurant_id] << {
            path: file_path,
            timestamp: timestamp,
            created_at: Time.strptime(timestamp, '%Y%m%d%H%M%S')
          }
        end
      end
      
      # Process each restaurant's backups
      backups_by_restaurant.each do |restaurant_id, backups|
        # Sort backups by timestamp (newest first)
        sorted_backups = backups.sort_by { |backup| backup[:created_at] }.reverse
        
        # Keep only the specified number of recent backups
        backups_to_delete = sorted_backups[keep_count..-1] || []
        
        # Delete old backups
        backups_to_delete.each do |backup|
          puts "Deleting old backup: #{backup[:path]}"
          File.delete(backup[:path]) if File.exist?(backup[:path])
        end
        
        puts "Kept #{[sorted_backups.size, keep_count].min} recent backups for restaurant #{restaurant_id}"
      end
      
      puts "Backup cleanup completed"
    end
    
    desc "Validate all backup files"
    task :validate => :environment do
      puts "Starting validation of all backup files"
      
      # Get all backup files
      export_dir = Rails.root.join('tmp', 'exports')
      FileUtils.mkdir_p(export_dir)
      
      backup_files = Dir.glob(File.join(export_dir, '*.zip'))
      
      puts "Found #{backup_files.count} backup files to validate"
      
      # Validate each backup file
      valid_count = 0
      invalid_count = 0
      
      backup_files.each do |file_path|
        file_name = File.basename(file_path)
        
        puts "Validating #{file_name}"
        
        begin
          # Validate the backup
          TenantBackupService.validate_backup(file_path)
          puts "  VALID: #{file_name}"
          valid_count += 1
        rescue => e
          puts "  INVALID: #{file_name} - #{e.message}"
          invalid_count += 1
        end
      end
      
      puts "Validation completed: #{valid_count} valid, #{invalid_count} invalid"
    end
    
    desc "Create a backup rotation schedule for all tenants"
    task :setup_rotation => :environment do
      puts "Setting up backup rotation schedule"
      
      # Get all active restaurants
      restaurants = Restaurant.where(active: true)
      
      # Create a crontab file
      crontab_file = Rails.root.join('tmp', 'tenant_backup_crontab')
      
      File.open(crontab_file, 'w') do |file|
        # Add header
        file.puts "# Tenant backup rotation schedule"
        file.puts "# Generated at #{Time.current}"
        file.puts "# Install with: crontab #{crontab_file}"
        file.puts ""
        
        # Add daily backup for all tenants
        file.puts "# Daily backup of all tenants at 2:00 AM"
        file.puts "0 2 * * * cd #{Rails.root} && RAILS_ENV=#{Rails.env} bundle exec rake tenant:backup:all"
        file.puts ""
        
        # Add weekly cleanup to keep 5 most recent backups
        file.puts "# Weekly cleanup of old backups, keeping 5 most recent per tenant"
        file.puts "0 3 * * 0 cd #{Rails.root} && RAILS_ENV=#{Rails.env} bundle exec rake tenant:backup:cleanup[5]"
        file.puts ""
        
        # Add monthly validation of all backups
        file.puts "# Monthly validation of all backup files"
        file.puts "0 4 1 * * cd #{Rails.root} && RAILS_ENV=#{Rails.env} bundle exec rake tenant:backup:validate"
      end
      
      puts "Backup rotation schedule created at #{crontab_file}"
      puts "Install with: crontab #{crontab_file}"
    end
  end
  
  namespace :restore do
    desc "Restore a tenant from a backup file"
    task :from_backup, [:backup_id, :target_restaurant_id] => :environment do |t, args|
      backup_id = args[:backup_id]
      target_restaurant_id = args[:target_restaurant_id]
      
      if backup_id.blank?
        puts "ERROR: Backup ID is required"
        puts "Usage: rake tenant:restore:from_backup[backup_id,target_restaurant_id]"
        exit 1
      end
      
      # Find the backup file
      export_dir = Rails.root.join('tmp', 'exports')
      backup_path = File.join(export_dir, "#{backup_id}.zip")
      
      unless File.exist?(backup_path)
        puts "ERROR: Backup file not found: #{backup_path}"
        exit 1
      end
      
      puts "Starting restore from backup #{backup_id} at #{Time.current}"
      
      # Determine restore options
      options = {}
      
      if target_restaurant_id.present?
        # Find the target restaurant
        target_restaurant = Restaurant.find_by(id: target_restaurant_id)
        
        unless target_restaurant
          puts "ERROR: Target restaurant with ID #{target_restaurant_id} not found"
          exit 1
        end
        
        puts "Restoring to existing restaurant: #{target_restaurant.name} (ID: #{target_restaurant.id})"
        options[:target_restaurant] = target_restaurant
        options[:skip_restaurant_creation] = true
      else
        puts "Restoring to new restaurant from backup"
        options[:skip_restaurant_creation] = false
      end
      
      begin
        # Import the tenant data
        restaurant = TenantBackupService.import_tenant(backup_path, options)
        puts "Restore completed for restaurant: #{restaurant.name} (ID: #{restaurant.id})"
      rescue => e
        puts "ERROR: Restore failed: #{e.message}"
        puts e.backtrace.join("\n")
        exit 1
      end
    end
    
    desc "Clone a tenant to a new restaurant"
    task :clone_tenant, [:source_restaurant_id, :new_restaurant_name] => :environment do |t, args|
      source_restaurant_id = args[:source_restaurant_id]
      new_restaurant_name = args[:new_restaurant_name]
      
      if source_restaurant_id.blank? || new_restaurant_name.blank?
        puts "ERROR: Source restaurant ID and new restaurant name are required"
        puts "Usage: rake tenant:restore:clone_tenant[source_restaurant_id,new_restaurant_name]"
        exit 1
      end
      
      # Find the source restaurant
      source_restaurant = Restaurant.find_by(id: source_restaurant_id)
      
      unless source_restaurant
        puts "ERROR: Source restaurant with ID #{source_restaurant_id} not found"
        exit 1
      end
      
      puts "Starting clone from #{source_restaurant.name} to #{new_restaurant_name} at #{Time.current}"
      
      begin
        # Clone the tenant
        new_restaurant = TenantBackupService.clone_tenant(source_restaurant, new_restaurant_name)
        puts "Clone completed: #{new_restaurant.name} (ID: #{new_restaurant.id})"
      rescue => e
        puts "ERROR: Clone failed: #{e.message}"
        puts e.backtrace.join("\n")
        exit 1
      end
    end
  end
end
