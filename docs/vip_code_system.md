# VIP Code System

The VIP Code System provides a way to generate, manage, and distribute access codes that grant customers VIP privileges when placing orders. This document outlines the backend implementation of the VIP code system.

## Overview

The VIP code system allows restaurant administrators to:

1. Generate individual or group VIP access codes
2. Manage code properties (name, usage limits, active status)
3. Send VIP codes to customers via email
4. Track code usage and analytics

## Database Schema

### VIP Access Codes

The system uses the `vip_access_codes` table with the following structure:

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| code | string | Unique access code |
| name | string | Descriptive name for the code |
| max_uses | integer | Maximum number of times the code can be used (null for unlimited) |
| current_uses | integer | Current usage count |
| expires_at | datetime | Expiration date (null for no expiration) |
| is_active | boolean | Whether the code is currently active |
| group_id | string | Group identifier for batch-generated codes |
| archived | boolean | Whether the code is archived |
| restaurant_id | integer | Associated restaurant |
| created_at | datetime | Creation timestamp |
| updated_at | datetime | Last update timestamp |

### VIP Code Recipients

The system also tracks recipients of VIP codes using the `vip_code_recipients` table:

| Column | Type | Description |
|--------|------|-------------|
| id | integer | Primary key |
| vip_access_code_id | integer | Foreign key to the VIP access code |
| email | string | Email address of the recipient |
| sent_at | datetime | When the code was sent to this recipient |
| created_at | datetime | Creation timestamp |
| updated_at | datetime | Last update timestamp |

## Models

### VipAccessCode

The `VipAccessCode` model (`app/models/vip_access_code.rb`) represents a VIP access code and includes:

- Validations for required fields
- Scopes for filtering codes
- Methods for checking validity and usage

```ruby
# Key methods in the VipAccessCode model
def valid_for_use?
  is_active && !archived && (!max_uses || current_uses < max_uses) && (!expires_at || expires_at > Time.current)
end

def increment_usage!
  increment!(:current_uses)
end
```

## Controllers

### VipAccessController

The `VipAccessController` (`app/controllers/vip_access_controller.rb`) handles VIP code validation and usage:

```ruby
# Key endpoints
POST /api/vip/validate  # Validates a VIP code without using it
POST /api/vip/use       # Validates and marks a VIP code as used
GET  /api/vip/codes     # Lists VIP codes (admin only)
POST /api/vip/codes     # Generates new VIP codes (admin only)
```

## Services

### VipCodeGenerator

The `VipCodeGenerator` service (`app/services/vip_code_generator.rb`) handles code generation:

```ruby
# Key methods
def self.generate_individual_codes(count, options = {})
  # Generates multiple individual codes
end

def self.generate_group_code(options = {})
  # Generates a single group code
end

def self.generate_code(prefix = nil)
  # Generates a unique code string
end
```

## Email Delivery

### VipCodeMailer

The `VipCodeMailer` (`app/mailers/vip_code_mailer.rb`) handles sending VIP codes to customers:

```ruby
# Key methods
def vip_code_notification(recipient_email, code, options = {})
  # Sends a single VIP code to a recipient
end
```

### SendVipCodesBatchJob

The `SendVipCodesBatchJob` (`app/jobs/send_vip_codes_batch_job.rb`) handles sending VIP codes in batches:

```ruby
# Key methods
def perform(email_list, code_ids, batch_size, current_batch)
  # Processes a batch of emails for sending VIP codes
end
```

## API Endpoints

### VIP Code Generation

```
POST /api/vip/codes/individual
```

Parameters:
- `count` (integer): Number of codes to generate
- `name` (string): Name for the codes
- `prefix` (string, optional): Custom prefix for the codes
- `max_uses` (integer, optional): Maximum number of uses per code

Response:
```json
[
  {
    "id": 1,
    "code": "VIP123456",
    "name": "Individual VIP",
    "max_uses": 5,
    "current_uses": 0,
    "is_active": true,
    "created_at": "2025-03-08T12:00:00Z"
  },
  ...
]
```

### Group Code Generation

```
POST /api/vip/codes/group
```

Parameters:
- `name` (string): Name for the code
- `prefix` (string, optional): Custom prefix for the code
- `max_uses` (integer, optional): Maximum number of uses

Response:
```json
{
  "id": 10,
  "code": "VIPGROUP789",
  "name": "Group VIP",
  "max_uses": 100,
  "current_uses": 0,
  "is_active": true,
  "group_id": "group_123",
  "created_at": "2025-03-08T12:00:00Z"
}
```

### VIP Code Validation

```
POST /api/vip/validate
```

Parameters:
- `code` (string): The VIP code to validate

Response:
```json
{
  "valid": true,
  "code": {
    "id": 1,
    "code": "VIP123456",
    "name": "Individual VIP"
  }
}
```

### VIP Code Usage

```
POST /api/vip/use
```

Parameters:
- `code` (string): The VIP code to use
- `order_id` (integer, optional): Associated order ID

Response:
```json
{
  "success": true,
  "code": {
    "id": 1,
    "code": "VIP123456",
    "name": "Individual VIP",
    "current_uses": 1,
    "max_uses": 5
  }
}
```

### Send VIP Codes via Email

```
POST /api/vip/codes/send
```

Parameters:
- `email_list` (array): List of recipient email addresses
- `code_ids` (array): List of VIP code IDs to send
- `batch_size` (integer, optional): Number of emails to process in each batch

Response:
```json
{
  "success": true,
  "total_recipients": 100,
  "batch_count": 2,
  "message": "VIP codes queued for sending"
}
```

### Bulk Send with New Codes

```
POST /api/vip/codes/bulk_send
```

Parameters:
- `email_list` (array): List of recipient email addresses
- `batch_size` (integer, optional): Number of emails to process in each batch
- `name` (string): Name for the generated codes
- `prefix` (string, optional): Custom prefix for the codes
- `max_uses` (integer, optional): Maximum number of uses per code

Response:
```json
{
  "success": true,
  "total_recipients": 100,
  "batch_count": 2,
  "message": "VIP codes generated and queued for sending"
}
```

## Usage Analytics

The system tracks VIP code usage and provides analytics through:

1. The `current_uses` field in the `vip_access_codes` table
2. Association with orders when a code is used
3. Analytics endpoints for admin dashboards

## Security Considerations

1. VIP code validation and usage endpoints are rate-limited to prevent brute force attacks
2. Admin-only endpoints require authentication and authorization
3. Codes are generated with sufficient entropy to prevent guessing
4. Email delivery is handled asynchronously to prevent blocking and improve performance

## Integration with Order System

When a customer uses a VIP code during checkout:

1. The code is validated using the `/api/vip/validate` endpoint
2. If valid, the order is marked as a VIP order
3. When the order is confirmed, the code usage is incremented using the `/api/vip/use` endpoint
4. VIP orders receive priority handling in the order queue

## Batch Processing

For large email campaigns, the system uses background jobs to process emails in batches:

1. The `SendVipCodesBatchJob` processes a subset of the email list
2. Each job sends emails to a configurable number of recipients
3. Jobs are scheduled with delays to prevent overwhelming the email service
4. Progress and status are tracked for admin monitoring
