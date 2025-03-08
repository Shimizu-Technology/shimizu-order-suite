# Schema Fix Instructions

This document provides instructions for fixing the schema inconsistency issue where the `vip_code` column exists in the schema.rb file but not in the actual production database.

## 1. Fix the Missing `vip_code` Column

We've created a migration to add the missing `vip_code` column to the orders table. To apply this migration:

```bash
# On your production server
cd /path/to/your/rails/app
rails db:migrate RAILS_ENV=production
```

This will add the missing `vip_code` column to the orders table if it doesn't already exist.

## 2. Check for Other Schema Inconsistencies

We've also created a verification script to check for other potential schema inconsistencies. To run this script:

```bash
# On your production server
cd /path/to/your/rails/app
RAILS_ENV=production rails runner script/verify_schema.rb
```

This script will:
1. Compare the columns defined in your schema.rb file with the actual columns in your database
2. Report any missing or extra columns
3. Help you identify other potential issues that might need to be fixed

## 3. Restart Your Rails Application

After applying the migration, restart your Rails application to ensure the changes take effect:

```bash
# If using Passenger
touch tmp/restart.txt

# If using Puma or another server, use the appropriate restart command
```

## 4. Preventing Future Schema Inconsistencies

To prevent similar issues in the future:

1. Always use conditional checks in migrations:
   ```ruby
   unless column_exists?(:table_name, :column_name)
     add_column :table_name, :column_name, :data_type
   end
   ```

2. Consider adding the verification script to your deployment process to catch inconsistencies early.

3. Ensure all migrations are properly run when deploying to production.
