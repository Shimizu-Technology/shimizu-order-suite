# **Database Export and Import Guide**

This guide explains how to export your local PostgreSQL database and import it to another environment. This is useful for:

- Sharing your database state with other developers
- Creating backups before major changes
- Setting up a new development environment quickly

## **1. Export (Dump) Your Local Database**

From your terminal:

```bash
pg_dump -U myapp_user -h localhost -p 5432 myapp_development > myapp_development_backup.sql
```

Parameters explained:
- `-U myapp_user`: The database username from your database.yml
- `-h localhost -p 5432`: Host and port from your database.yml
- `myapp_development`: The name of your database
- `> myapp_development_backup.sql`: Writes the dump to a file

This backup file will include both your database schema (structure) and data.

**Note**: If your local PostgreSQL is set to "peer" or "trust" authentication, you might not need to specify `-U`, `-h`, or `-p`. Use whichever combination works in your environment.

## **2. Drop and Re-Create Your Local Database**

If you want to test this backup or need to reset your database:

```bash
# 1. Drop your existing database:
dropdb -U myapp_user -h localhost -p 5432 myapp_development

# 2. Re-create a fresh, empty database:
createdb -U myapp_user -h localhost -p 5432 myapp_development
```

## **3. Restore from the Backup File**

Load the backup into your freshly re-created database:

```bash
psql -U myapp_user -h localhost -p 5432 myapp_development < myapp_development_backup.sql
```

This command will read the structure and data from the backup file and import it into your newly created database.

## **4. Verify the Import**

Run a quick check to verify that all your tables and data are there:

```bash
rails dbconsole
```

You can then run some basic queries to check that your data is present:

```sql
SELECT COUNT(*) FROM restaurants;
SELECT COUNT(*) FROM users;
-- etc.
```

Exit the console with `\q` when done.

## **Common Variations**

### **Custom-Format Dump**

For a compressed format that's more flexible during restore:

```bash
# Export in custom format
pg_dump -Fc -U myapp_user -h localhost -p 5432 myapp_development > myapp_development_backup.dump

# Restore from custom format
pg_restore -d myapp_development -U myapp_user myapp_development_backup.dump
```

This format offers better compression and more restore options.

### **Troubleshooting**

- **No Password Prompt**: If PostgreSQL is configured for trust/peer authentication locally, you might not need `-U`, or you may omit password prompts.

- **pg_dump / psql Not Found**: If your system doesn't recognize these commands, you may need to install PostgreSQL tools or add them to your PATH:
  ```bash
  # For macOS with Homebrew
  brew install postgresql
  ```

- **Permission Denied**: If you get permission errors, make sure your database user has the necessary privileges.

## **Using for Team Development**

When onboarding new team members:

1. An existing developer exports their database with test data
2. They share the SQL dump file with the new team member
3. The new team member creates their database and imports the dump
4. This ensures everyone has the same data to work with

This approach is more efficient than relying on seeds when the database structure is complex or frequently changing.
