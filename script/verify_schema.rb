#!/usr/bin/env ruby
# script/verify_schema.rb
require_relative '../config/environment'

puts "Checking schema consistency..."
puts "-----------------------------"

inconsistencies_found = false

ActiveRecord::Base.connection.tables.each do |table|
  # Skip internal Rails tables
  next if ['schema_migrations', 'ar_internal_metadata'].include?(table)
  
  # Get columns from schema.rb
  expected_columns = ActiveRecord::Base.connection.columns(table).map(&:name).sort
  
  # Get columns directly from database
  actual_columns = ActiveRecord::Base.connection.exec_query(
    "SELECT column_name FROM information_schema.columns WHERE table_name = '#{table}'"
  ).rows.flatten.sort
  
  # Find missing columns
  missing_columns = expected_columns - actual_columns
  extra_columns = actual_columns - expected_columns
  
  if missing_columns.any? || extra_columns.any?
    inconsistencies_found = true
    puts "\n[!] Table '#{table}' has inconsistencies:"
    
    if missing_columns.any?
      puts "   - Missing columns (in schema.rb but not in database): #{missing_columns.join(', ')}"
    end
    
    if extra_columns.any?
      puts "   - Extra columns (in database but not in schema.rb): #{extra_columns.join(', ')}"
    end
  end
end

unless inconsistencies_found
  puts "\n[✓] All tables consistent between schema.rb and database!"
end
