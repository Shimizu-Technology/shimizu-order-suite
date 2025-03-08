# Migration Best Practices

This document outlines best practices for creating and managing database migrations in the Hafaloha application to prevent schema inconsistencies.

## Writing Safe Migrations

Always write idempotent migrations that can safely run multiple times without causing errors or duplicate changes.

### Adding Columns

```ruby
def change
  unless column_exists?(:table_name, :column_name)
    add_column :table_name, :column_name, :data_type
  end
end
```

### Creating Tables

```ruby
def change
  create_table :table_name, if_not_exists: true do |t|
    # columns...
  end
end
```

### Adding Indexes

```ruby
def change
  unless index_exists?(:table_name, :column_name)
    add_index :table_name, :column_name
  end
end
```

### Removing Columns

```ruby
def change
  if column_exists?(:table_name, :column_name)
    remove_column :table_name, :column_name
  end
end
```

### Changing Column Types

```ruby
def change
  if column_exists?(:table_name, :column_name)
    change_column :table_name, :column_name, :new_type
  end
end
```

## Deployment Process

1. Write idempotent migrations
2. Deploy code to Render
3. SSH into the Render instance
4. Run the deployment script: `./bin/deploy.sh`
5. Restart the application from the Render dashboard

## Schema Verification

We've implemented several layers of schema verification:

1. **Startup Verification**: The application checks schema integrity on startup via the `schema_verification.rb` initializer.
2. **Health Check Endpoint**: The `/health/check` endpoint verifies schema integrity and can be used for monitoring.
3. **Verification Script**: The `script/verify_schema.rb` script can be run manually to check for schema inconsistencies.

## Handling Schema Inconsistencies

If you discover a schema inconsistency:

1. Create a migration that checks for the missing column/table and adds it if needed
2. Run the migration in production
3. Verify the schema is now consistent using the verification script
4. Restart the application

## Common Pitfalls to Avoid

1. **Assuming migrations always run**: Always check if columns/tables exist before modifying them
2. **Not testing migrations**: Test migrations in a staging environment before deploying to production
3. **Forgetting to restart the application**: After running migrations, always restart the application
4. **Ignoring schema verification warnings**: Take schema verification warnings seriously and address them immediately

## Monitoring Schema Health

1. Configure the `/health/check` endpoint as a health check in Render
2. Set up alerts for schema inconsistencies
3. Periodically run the verification script to check for issues

By following these practices, we can prevent schema inconsistencies and ensure a smooth deployment process.
