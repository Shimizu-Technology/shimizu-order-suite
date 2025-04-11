# app/services/tenant_backup_service.rb
#
# The TenantBackupService is responsible for exporting and importing tenant data
# for disaster recovery and migration purposes. It provides methods to:
# - Export a tenant's data to a portable format
# - Import tenant data from a backup
# - Validate backup integrity
# - Migrate tenant data between environments
#
class TenantBackupService
  class << self
    # Export all data for a specific tenant
    # @param restaurant [Restaurant] the tenant to export
    # @param options [Hash] export options
    # @return [String] path to the exported data file
    def export_tenant(restaurant, options = {})
      raise ArgumentError, "Restaurant is required" unless restaurant.is_a?(Restaurant)
      
      # Create a unique export ID
      export_id = "tenant_export_#{restaurant.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}"
      
      # Create a temporary directory for the export
      export_dir = Rails.root.join('tmp', 'exports', export_id)
      FileUtils.mkdir_p(export_dir)
      
      # Create the export manifest
      manifest = {
        export_id: export_id,
        restaurant_id: restaurant.id,
        restaurant_name: restaurant.name,
        exported_at: Time.current,
        exported_by: options[:user_id],
        version: '1.0',
        tables: {}
      }
      
      # Export each model's data
      tenant_models.each do |model|
        next unless model.column_names.include?('restaurant_id')
        
        table_name = model.table_name
        records = model.where(restaurant_id: restaurant.id).to_a
        
        # Skip if no records found and not explicitly included
        next if records.empty? && !options[:include_empty_tables]
        
        # Export the records to a JSON file
        file_path = export_dir.join("#{table_name}.json")
        File.write(file_path, records.to_json)
        
        # Update the manifest
        manifest[:tables][table_name] = {
          count: records.size,
          file: "#{table_name}.json"
        }
      end
      
      # Write the manifest file
      manifest_path = export_dir.join('manifest.json')
      File.write(manifest_path, manifest.to_json)
      
      # Create a compressed archive of the export
      archive_path = Rails.root.join('tmp', 'exports', "#{export_id}.zip")
      
      # Use the zip command to create the archive
      system("cd #{export_dir} && zip -r #{archive_path} .")
      
      # Log the export
      Rails.logger.info("Tenant export completed for restaurant #{restaurant.id}: #{archive_path}")
      
      # Return the path to the archive
      archive_path.to_s
    end
    
    # Import tenant data from a backup
    # @param archive_path [String] path to the backup archive
    # @param options [Hash] import options
    # @return [Restaurant] the imported restaurant
    def import_tenant(archive_path, options = {})
      raise ArgumentError, "Archive path is required" unless archive_path.present?
      raise ArgumentError, "Archive file does not exist" unless File.exist?(archive_path)
      
      # Create a temporary directory for the import
      import_id = "tenant_import_#{Time.current.strftime('%Y%m%d%H%M%S')}"
      import_dir = Rails.root.join('tmp', 'imports', import_id)
      FileUtils.mkdir_p(import_dir)
      
      # Extract the archive
      system("unzip -q #{archive_path} -d #{import_dir}")
      
      # Read the manifest
      manifest_path = import_dir.join('manifest.json')
      raise ArgumentError, "Invalid backup: manifest.json not found" unless File.exist?(manifest_path)
      
      manifest = JSON.parse(File.read(manifest_path))
      
      # Validate the manifest
      validate_manifest(manifest)
      
      # Start a transaction to ensure all-or-nothing import
      ActiveRecord::Base.transaction do
        # Create or update the restaurant
        restaurant = import_restaurant(manifest, options)
        
        # Import data for each table
        manifest['tables'].each do |table_name, table_info|
          import_table(table_name, table_info, import_dir, restaurant, options)
        end
        
        # Return the imported restaurant
        restaurant
      end
    end
    
    # Validate a backup archive
    # @param archive_path [String] path to the backup archive
    # @return [Boolean] true if valid, raises exception if invalid
    def validate_backup(archive_path)
      raise ArgumentError, "Archive path is required" unless archive_path.present?
      raise ArgumentError, "Archive file does not exist" unless File.exist?(archive_path)
      
      # Create a temporary directory for validation
      validation_id = "tenant_validation_#{Time.current.strftime('%Y%m%d%H%M%S')}"
      validation_dir = Rails.root.join('tmp', 'validations', validation_id)
      FileUtils.mkdir_p(validation_dir)
      
      begin
        # Extract the archive
        system("unzip -q #{archive_path} -d #{validation_dir}")
        
        # Read the manifest
        manifest_path = validation_dir.join('manifest.json')
        raise ArgumentError, "Invalid backup: manifest.json not found" unless File.exist?(manifest_path)
        
        manifest = JSON.parse(File.read(manifest_path))
        
        # Validate the manifest
        validate_manifest(manifest)
        
        # Validate each table file
        manifest['tables'].each do |table_name, table_info|
          file_path = validation_dir.join(table_info['file'])
          raise ArgumentError, "Invalid backup: #{table_info['file']} not found" unless File.exist?(file_path)
          
          # Validate JSON format
          begin
            records = JSON.parse(File.read(file_path))
            raise ArgumentError, "Invalid backup: #{table_info['file']} is not an array" unless records.is_a?(Array)
          rescue JSON::ParserError
            raise ArgumentError, "Invalid backup: #{table_info['file']} is not valid JSON"
          end
        end
        
        # If we get here, the backup is valid
        true
      ensure
        # Clean up the validation directory
        FileUtils.rm_rf(validation_dir)
      end
    end
    
    # Clone a tenant to a new restaurant
    # @param source_restaurant [Restaurant] the source tenant
    # @param new_name [String] name for the new restaurant
    # @param options [Hash] clone options
    # @return [Restaurant] the cloned restaurant
    def clone_tenant(source_restaurant, new_name, options = {})
      raise ArgumentError, "Source restaurant is required" unless source_restaurant.is_a?(Restaurant)
      raise ArgumentError, "New name is required" unless new_name.present?
      
      # Create a temporary directory for the clone operation
      clone_id = "tenant_clone_#{source_restaurant.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}"
      clone_dir = Rails.root.join('tmp', 'clones', clone_id)
      FileUtils.mkdir_p(clone_dir)
      
      begin
        # Export the source tenant to a temporary file
        archive_path = export_tenant(source_restaurant, include_empty_tables: true)
        
        # Start a transaction to ensure all-or-nothing clone
        ActiveRecord::Base.transaction do
          # Create a new restaurant for the clone
          new_restaurant = Restaurant.create!(
            name: new_name,
            active: options[:active].nil? ? true : options[:active],
            address: source_restaurant.address,
            phone: source_restaurant.phone,
            email: source_restaurant.email,
            website: source_restaurant.website,
            description: source_restaurant.description,
            cuisine_type: source_restaurant.cuisine_type,
            opening_hours: source_restaurant.opening_hours,
            logo_url: source_restaurant.logo_url,
            banner_url: source_restaurant.banner_url,
            theme_color: source_restaurant.theme_color,
            secondary_color: source_restaurant.secondary_color
          )
          
          # Import the data with the new restaurant
          import_options = options.merge(
            target_restaurant: new_restaurant,
            skip_restaurant_creation: true,
            preserve_ids: false,
            update_existing: false
          )
          
          # Import the data
          import_tenant(archive_path, import_options)
          
          # Log the clone operation
          AuditLog.log_data_modification(
            User.find_by(id: options[:user_id]),
            'clone',
            'Restaurant',
            source_restaurant.id,
            'system',
            { 
              source_restaurant_id: source_restaurant.id,
              new_restaurant_id: new_restaurant.id,
              new_restaurant_name: new_name,
              clone_id: clone_id
            }
          ) if options[:user_id].present?
          
          # Return the new restaurant
          new_restaurant
        end
      ensure
        # Clean up the clone directory
        FileUtils.rm_rf(clone_dir) if File.directory?(clone_dir)
      end
    end
    
    # Migrate a tenant from one environment to another
    # @param export_path [String] path to the exported tenant data
    # @param target_env [String] target environment (e.g., 'production', 'staging')
    # @param options [Hash] migration options
    # @return [Boolean] true if successful
    def migrate_tenant(export_path, target_env, options = {})
      raise ArgumentError, "Export path is required" unless export_path.present?
      raise ArgumentError, "Target environment is required" unless target_env.present?
      
      # Validate the target environment
      valid_environments = ['staging', 'production']
      unless valid_environments.include?(target_env)
        raise ArgumentError, "Invalid target environment: #{target_env}"
      end
      
      # Validate the backup
      validate_backup(export_path)
      
      # Get the API endpoint for the target environment
      api_endpoint = case target_env
                    when 'staging'
                      ENV['STAGING_API_ENDPOINT']
                    when 'production'
                      ENV['PRODUCTION_API_ENDPOINT']
                    end
      
      # Get the API key for the target environment
      api_key = case target_env
                when 'staging'
                  ENV['STAGING_API_KEY']
                when 'production'
                  ENV['PRODUCTION_API_KEY']
                end
      
      # Ensure we have the necessary configuration
      unless api_endpoint.present? && api_key.present?
        raise ArgumentError, "Missing API configuration for #{target_env} environment"
      end
      
      # Create a temporary directory for the migration
      migration_id = "tenant_migration_#{Time.current.strftime('%Y%m%d%H%M%S')}"
      migration_dir = Rails.root.join('tmp', 'migrations', migration_id)
      FileUtils.mkdir_p(migration_dir)
      
      begin
        # Copy the backup file to the migration directory
        backup_filename = File.basename(export_path)
        migration_file = File.join(migration_dir, backup_filename)
        FileUtils.cp(export_path, migration_file)
        
        # Create a multipart form request to the target environment
        uri = URI.parse("#{api_endpoint}/api/v1/admin/tenant_backup/import_tenant")
        
        # Create the HTTP request
        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{api_key}"
        
        # Create a multipart form
        form_data = [
          ['backup_file', File.open(migration_file)],
          ['options', options.to_json]
        ]
        
        request.set_form(form_data, 'multipart/form-data')
        
        # Send the request
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        response = http.request(request)
        
        # Check the response
        if response.code.to_i >= 200 && response.code.to_i < 300
          # Log the migration
          AuditLog.log_data_modification(
            User.find_by(id: options[:user_id]),
            'migrate',
            'Backup',
            backup_filename,
            'system',
            { 
              target_environment: target_env,
              migration_id: migration_id,
              response: response.body
            }
          ) if options[:user_id].present?
          
          # Return success
          true
        else
          # Log the failure
          AuditLog.log_data_modification(
            User.find_by(id: options[:user_id]),
            'migrate_failed',
            'Backup',
            backup_filename,
            'system',
            { 
              target_environment: target_env,
              migration_id: migration_id,
              response: response.body,
              status_code: response.code
            }
          ) if options[:user_id].present?
          
          # Raise an error
          raise "Migration failed: #{response.body}"
        end
      ensure
        # Clean up
        FileUtils.rm_rf(migration_dir) if File.directory?(migration_dir)
      end
      
      # Determine the target server based on the environment
      target_server = case target_env
                      when 'production'
                        ENV['PRODUCTION_SERVER']
                      when 'staging'
                        ENV['STAGING_SERVER']
                      else
                        raise ArgumentError, "Unknown target environment: #{target_env}"
                      end
      
      # Transfer the file to the target server
      remote_path = "/tmp/tenant_migration_#{File.basename(export_path)}"
      system("scp #{export_path} #{target_server}:#{remote_path}")
      
      # Execute the import on the target server
      ssh_command = [
        "ssh #{target_server}",
        "\"cd #{ENV['REMOTE_APP_PATH']} &&",
        "RAILS_ENV=#{target_env}",
        "bundle exec rails runner",
        "'TenantBackupService.import_tenant(\\\"#{remote_path}\\\", #{options.to_json})'\""
      ].join(' ')
      
      # Execute the command
      result = system(ssh_command)
      
      # Clean up the remote file
      system("ssh #{target_server} 'rm #{remote_path}'")
      
      # Return the result
      result
    end
    
    private
    
    # Get all models that belong to a tenant
    # @return [Array<Class>] array of model classes
    def tenant_models
      # Get all models that inherit from ApplicationRecord
      Rails.application.eager_load!
      ApplicationRecord.descendants.select do |model|
        # Only include models with a restaurant_id column
        model.column_names.include?('restaurant_id')
      end
    end
    
    # Validate the manifest structure
    # @param manifest [Hash] the manifest to validate
    # @return [Boolean] true if valid, raises exception if invalid
    def validate_manifest(manifest)
      required_keys = ['export_id', 'restaurant_id', 'restaurant_name', 'exported_at', 'version', 'tables']
      missing_keys = required_keys - manifest.keys
      
      raise ArgumentError, "Invalid manifest: missing keys #{missing_keys.join(', ')}" if missing_keys.any?
      raise ArgumentError, "Invalid manifest: tables must be a hash" unless manifest['tables'].is_a?(Hash)
      
      true
    end
    
    # Import or update the restaurant
    # @param manifest [Hash] the import manifest
    # @param options [Hash] import options
    # @return [Restaurant] the imported restaurant
    def import_restaurant(manifest, options)
      if options[:target_restaurant]
        # Use the provided restaurant
        options[:target_restaurant]
      elsif options[:skip_restaurant_creation]
        # Find the existing restaurant
        Restaurant.find_by(id: manifest['restaurant_id']) || 
          raise(ArgumentError, "Restaurant with ID #{manifest['restaurant_id']} not found")
      else
        # Create a new restaurant
        restaurant = Restaurant.new(
          name: manifest['restaurant_name'],
          active: options[:activate_restaurant] || false
          # Other attributes would be set here
        )
        
        # Save the restaurant
        restaurant.save!
        restaurant
      end
    end
    
    # Import data for a specific table
    # @param table_name [String] the table name
    # @param table_info [Hash] table information from the manifest
    # @param import_dir [Pathname] path to the import directory
    # @param restaurant [Restaurant] the target restaurant
    # @param options [Hash] import options
    # @return [void]
    def import_table(table_name, table_info, import_dir, restaurant, options)
      # Skip tables in the exclusion list
      return if options[:exclude_tables]&.include?(table_name)
      
      # Get the model class
      model_class = table_name.classify.constantize
      
      # Read the records from the file
      file_path = import_dir.join(table_info['file'])
      records = JSON.parse(File.read(file_path))
      
      # Clear existing records if requested
      if options[:clear_existing_data]
        model_class.where(restaurant_id: restaurant.id).delete_all
      end
      
      # Import each record
      records.each do |record_data|
        # Update the restaurant_id to the target restaurant
        record_data['restaurant_id'] = restaurant.id
        
        # Remove the id to create a new record
        record_id = record_data.delete('id')
        
        # Find or initialize the record
        if options[:update_existing] && record_id
          record = model_class.find_by(id: record_id)
          if record
            record.assign_attributes(record_data)
          else
            record = model_class.new(record_data)
          end
        else
          record = model_class.new(record_data)
        end
        
        # Save the record
        record.save!
      end
    end
  end
end
