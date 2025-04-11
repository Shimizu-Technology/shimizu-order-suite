# Disaster Recovery Procedures for Shimizu Order Suite

This document outlines the disaster recovery procedures for the Shimizu Order Suite multi-tenant platform. It provides step-by-step instructions for backing up tenant data, restoring from backups, and migrating tenants between environments.

## Table of Contents

1. [Overview](#overview)
2. [Backup Procedures](#backup-procedures)
3. [Restore Procedures](#restore-procedures)
4. [Tenant Migration](#tenant-migration)
5. [Emergency Response](#emergency-response)
6. [Testing and Validation](#testing-and-validation)

## Overview

The Shimizu Order Suite platform implements a comprehensive disaster recovery strategy to ensure business continuity in case of system failures, data corruption, or other incidents. The strategy includes:

- Regular automated backups of all tenant data
- Tenant-specific backup and restore capabilities
- Ability to migrate tenants between environments
- Validation procedures to ensure backup integrity
- Emergency response procedures for critical incidents

## Backup Procedures

### Automated Backups

The system performs automated backups of all tenant data on the following schedule:

- **Daily backups**: All active tenants are backed up daily at 2:00 AM
- **Weekly cleanup**: Old backups are cleaned up weekly, keeping the 5 most recent backups per tenant
- **Monthly validation**: All backup files are validated monthly to ensure their integrity

These automated backups are configured using the `tenant:backup:setup_rotation` rake task, which creates a crontab file with the appropriate schedule.

### Manual Backups

Administrators can initiate manual backups through the admin interface or using rake tasks:

#### Using the Admin Interface

1. Navigate to Admin > Tenant Backup
2. Click on "Export Tenant" for the desired tenant
3. Wait for the backup job to complete
4. Download the backup file if needed

#### Using Rake Tasks

To backup all tenants:

```bash
bundle exec rake tenant:backup:all
```

To backup a specific tenant:

```bash
bundle exec rake tenant:backup:tenant[restaurant_id]
```

### Backup Storage

Backup files are stored in the `tmp/exports` directory on the application server. Each backup file is a ZIP archive containing:

- A manifest file with metadata about the backup
- JSON files containing the data for each table
- Timestamps and tenant information in the filename

For production environments, these backups should be copied to an external storage system (e.g., AWS S3, Google Cloud Storage) for additional redundancy.

## Restore Procedures

### Restoring a Tenant

Tenant data can be restored from a backup in several ways:

#### Using the Admin Interface

1. Navigate to Admin > Tenant Backup
2. Click on "Backups" to view available backups
3. Select a backup and click "Restore"
4. Choose whether to restore to the original tenant or create a new tenant
5. Confirm the restore operation
6. Monitor the restore job progress

#### Using Rake Tasks

To restore a tenant from a backup:

```bash
bundle exec rake tenant:restore:from_backup[backup_id,target_restaurant_id]
```

If `target_restaurant_id` is omitted, a new restaurant will be created from the backup.

### Cloning a Tenant

Tenants can be cloned to create a new tenant with the same data:

#### Using the Admin Interface

1. Navigate to Admin > Tenant Backup
2. Click on "Clone Tenant"
3. Select the source tenant and enter a name for the new tenant
4. Confirm the clone operation
5. Monitor the clone job progress

#### Using Rake Tasks

To clone a tenant:

```bash
bundle exec rake tenant:restore:clone_tenant[source_restaurant_id,new_restaurant_name]
```

## Tenant Migration

Tenants can be migrated between environments (e.g., from staging to production):

### Migration Process

1. Export the tenant data from the source environment
2. Transfer the backup file to the target environment
3. Import the tenant data in the target environment

#### Using the Admin Interface

1. Navigate to Admin > Tenant Backup
2. Click on "Migrate Tenant"
3. Select the backup and target environment
4. Confirm the migration operation
5. Monitor the migration job progress

#### Using TenantBackupService Directly

```ruby
# Export the tenant
export_path = TenantBackupService.export_tenant(restaurant)

# Migrate to target environment
TenantBackupService.migrate_tenant(export_path, 'production')
```

## Emergency Response

In case of a critical incident affecting tenant data:

### Data Corruption

1. Identify the affected tenant(s)
2. Stop all write operations to the affected tenant(s)
3. Assess the extent of the corruption
4. Restore the tenant(s) from the most recent valid backup
5. Validate the restored data
6. Resume operations

### System Failure

1. Activate the standby system if available
2. Restore the database from backups
3. Restore application code and configuration
4. Validate system functionality
5. Resume operations

### Security Breach

1. Isolate the affected tenant(s)
2. Revoke compromised credentials
3. Assess the extent of the breach
4. Restore the tenant(s) from the last known good backup
5. Apply security patches and updates
6. Resume operations with enhanced monitoring

## Testing and Validation

Regular testing of the disaster recovery procedures is essential to ensure their effectiveness:

### Backup Validation

Validate backups using the built-in validation tool:

```bash
bundle exec rake tenant:backup:validate
```

### Restore Testing

Periodically test the restore process by:

1. Creating a test tenant
2. Populating it with test data
3. Backing up the tenant
4. Restoring the tenant to a different name
5. Verifying that all data is correctly restored

### Disaster Recovery Drills

Conduct regular disaster recovery drills to ensure that:

1. All team members are familiar with the procedures
2. The procedures are effective and efficient
3. Recovery time objectives (RTOs) and recovery point objectives (RPOs) are met

Document the results of each drill and update the procedures as needed.

## Conclusion

By following these disaster recovery procedures, the Shimizu Order Suite platform can maintain high availability and data integrity even in the face of unexpected incidents. Regular testing and validation of these procedures is essential to ensure their effectiveness.

For questions or assistance, contact the Shimizu Technology support team.
