# **Hafaloha Backend (Rails API)**

A multi-tenant SaaS platform for restaurant reservation and order management.

## **Overview**

Hafaloha is a SaaS (Software as a Service) platform that enables multiple restaurants to:

- Manage **reservations** and table layouts
- Take **food orders** online
- Send **notifications** via multiple channels
- Track **inventory** and **menu items**
- Sell **merchandise** with separate collection-based organization
- Analyze **business data** and metrics

The backend is built with **Ruby on Rails** in API-only mode, with a multi-tenant architecture that ensures proper data isolation between different restaurants.

---

## **Architecture Overview**

### Core Components

- **Rails API** (API-only mode)  
- **PostgreSQL** for the primary database
- **Redis** for Sidekiq job queue  
- **Sidekiq** for background job processing
- **JWT Authentication** with restaurant context
- **Multi-tenant** data isolation through default scopes
- **CORS configuration** for restaurant-specific frontend origins

### External Integrations

- **AWS S3** for image storage
- **SendGrid** for email notifications
- **ClickSend** for SMS notifications
- **Wassenger** for WhatsApp group messaging
- **PayPal** for payment processing with SDK integration
- **Stripe** for credit card payment processing with webhooks

### Data Flow

1. **API Requests** come in through controllers
2. **Restaurant Context** is automatically applied based on JWT or params
3. **Database Queries** are automatically filtered by restaurant
4. **Background Jobs** process notifications asynchronously
5. **CORS Configuration** allows specific frontend origins per restaurant

---

## **Recent Features**

### Inventory Tracking System

The platform includes a comprehensive inventory tracking system for both menu items and merchandise, allowing restaurants to:

- Enable/disable inventory tracking per item
- Set and monitor stock quantities
- Record damaged items with reasons and timestamps
- View audit history of all inventory changes
- Configure low stock thresholds for automated status updates
- Automatically update item availability based on inventory levels
- Perform bulk inventory operations
- Generate inventory reports

For detailed documentation, see [Inventory Tracking System Documentation](docs/inventory_tracking_system.md).

### Payment Processing System

The platform supports multiple payment methods and advanced payment operations:

- PayPal integration with SDK for direct checkout
- Stripe integration with webhooks for payment processing
- Order payment history tracking
- Refund processing (full or partial)
- Additional payment collection
- Store credit system for customer account balances

For detailed documentation, see:
- [Payment Processing Documentation](docs/payment_processing.md)
- [PayPal Integration Documentation](docs/paypal_integration.md)
- [Stripe Integration Documentation](docs/stripe_integration.md)

### Enhanced Notification System

The notification system has been expanded to include:

- Customizable notification templates
- Multiple delivery channels (email, SMS, WhatsApp)
- Notification history tracking
- Scheduled notifications
- Batch processing for notifications

For detailed documentation, see:
- [Notification System Documentation](docs/notification_system.md)
- [SMS Notification System Documentation](docs/sms_notification_system.md)

### Store Credit System

The platform now includes a comprehensive store credit system:

- Customer account balances with expiration dates
- Transaction history tracking
- Integration with order payment system
- Refund-to-store-credit functionality
- Admin tools for managing customer credits

For detailed documentation, see [Store Credit System Documentation](docs/store_credit_system.md).

### Merchandise Categories and Stock Management

The merchandise system now includes:

- Category-based organization for merchandise items
- Stock auditing for merchandise items
- Low stock threshold configuration
- Multiple images per merchandise item
- Enhanced filtering capabilities

For detailed documentation, see [Inventory Tracking System Documentation](docs/inventory_tracking_system.md).

### Custom Pickup Locations

Restaurants can now configure custom pickup locations for orders, providing more flexibility in order fulfillment logistics.

---

## **Multi-tenant Architecture**

Hafaloha uses a multi-tenant architecture where all restaurants share the same database, but data is isolated through application-level controls. This provides efficient resource utilization while ensuring proper data separation.

For comprehensive documentation on the multi-tenant architecture, see [Multi-tenant Architecture Documentation](docs/multi_tenant_architecture.md).

### Key Components of Multi-tenancy

#### 1. Restaurant Scope

All controllers include the `RestaurantScope` concern, which:
- Extracts the current restaurant from JWT tokens or request params
- Sets a thread-local variable for the current request
- Ensures all database queries are properly filtered by restaurant_id

```ruby
# app/controllers/concerns/restaurant_scope.rb
module RestaurantScope
  extend ActiveSupport::Concern
  
  included do
    before_action :set_restaurant_scope
  end
  
  private
  
  def set_restaurant_scope
    # For super_admin users who can access multiple restaurants
    if current_user&.role == 'super_admin'
      # Allow super_admin to specify which restaurant to work with
      @current_restaurant = if params[:restaurant_id].present?
                             Restaurant.find_by(id: params[:restaurant_id])
                           else
                             nil # Super admins can access global endpoints without restaurant context
                           end
    else
      # For regular users, always use their associated restaurant
      @current_restaurant = current_user&.restaurant
      
      # If no restaurant is associated and this isn't a public endpoint,
      # return an error
      unless @current_restaurant || public_endpoint?
        render json: { error: "Restaurant context required" }, status: :unprocessable_entity
        return
      end
    end
    
    # Make current_restaurant available to models for default scoping
    ActiveRecord::Base.current_restaurant = @current_restaurant
  end
  
  # Override this method in controllers that have public endpoints
  def public_endpoint?
    false
  end
end
```

#### 2. Default Scopes in Models

All models that contain restaurant-specific data use default scoping to ensure data isolation:

```ruby
# In ApplicationRecord
def self.apply_default_scope
  default_scope { with_restaurant_scope }
end

# In models
class Order < ApplicationRecord
  apply_default_scope
  belongs_to :restaurant
  # ...
end
```

For indirectly associated models, custom scope methods ensure proper filtering:

```ruby
# Example for models that access restaurant through associations
def self.with_restaurant_scope
  if current_restaurant
    joins(option_group: { menu_item: :menu }).where(menus: { restaurant_id: current_restaurant.id })
  else
    all
  end
end
```

#### 3. Public Endpoints

Some endpoints need to be accessible without restaurant context (e.g., login, signup, public restaurant data). These override the `public_endpoint?` method:

```ruby
def public_endpoint?
  action_name.in?(['create', 'verify_phone', 'resend_code'])
end
```

For example, the RestaurantsController allows public access to the `show` action:

```ruby
class RestaurantsController < ApplicationController
  before_action :authorize_request, except: [:show]
  before_action :set_restaurant, only: [:show, :update, :destroy]
  
  # GET /restaurants/:id
  def show
    # Skip authorization check for public access
    if current_user.present?
      unless current_user.role == "super_admin" || current_user.restaurant_id == @restaurant.id
        return render json: { error: "Forbidden" }, status: :forbidden
      end
    end

    render json: restaurant_json(@restaurant)
  end
  
  # ...
end
```

#### 4. Dynamic CORS Configuration

Each restaurant can configure its own allowed frontend origins:

```ruby
# In Restaurant model
attribute :allowed_origins, :string, array: true, default: []

# In CORS configuration
origins lambda { |source, env|
  request_origin = env["HTTP_ORIGIN"]
  
  # Check if origin is allowed for any restaurant
  Restaurant.where("allowed_origins @> ARRAY[?]::varchar[]", [request_origin]).exists? ||
  request_origin == 'http://localhost:5173' # Development exception
}
```

---

## **Key Models and Relationships**

- **Restaurant**: The central model for tenant isolation
  - Has many users, menus, layouts, reservations, orders, vip_access_codes
  - Has many merchandise_collections and merchandise_items through associations
  - Stores configuration including allowed CORS origins
  - Contains basic information like name, address, phone number, time zone
  - Includes vip_enabled flag to toggle VIP-only checkout mode
  - Has current_merchandise_collection_id to set active merchandise collection
  - Has custom_pickup_location for order fulfillment flexibility

- **SiteSetting**: Stores site-wide settings for each restaurant
  - Belongs to a restaurant
  - Contains hero image and spinner image URLs

- **User**: Authentication and authorization
  - Belongs to a restaurant
  - Has roles (customer, admin, super_admin)

- **Reservation**: Table bookings
  - Belongs to restaurant
  - Has many seat_allocations

- **Order**: Food orders
  - Belongs to restaurant
  - Optional user association for guest orders
  - Has many order_acknowledgments for tracking admin notifications
  - Optional vip_access_code association for VIP-only orders
  - Has many merchandise_items (for merchandise purchases)
  - Has many order_payments for payment history tracking
  - Includes payment_status for tracking payment state

- **OrderPayment**: Payment history for orders
  - Belongs to order
  - Tracks payment method, amount, status, and timestamps
  - Includes refunded_items for partial refunds

- **StoreCredit**: Customer account balances
  - Belongs to user
  - Belongs to restaurant
  - Tracks balance, expiration, and usage history

- **OrderAcknowledgment**: Tracks which orders have been acknowledged by which admin users
  - Belongs to order
  - Belongs to user
  - Ensures order notifications persist across page refreshes

- **VipAccessCode**: VIP access control
  - Belongs to restaurant
  - Has many orders
  - Contains code, name, usage limits, and expiration
  - Tracks current usage count
  - Can be individual or part of a group (via group_id)

- **Menu/MenuItem/Category**: Menu management
  - All belong to restaurant directly or through associations
  - Menu items can have option groups and options
  - Menu items can have advance_notice_hours for items requiring preparation time (e.g., 24 hours)
  - Restaurants can have multiple menus with one set as active via current_menu_id
  - Menus can be cloned to create variations for special events
  - Menu items have inventory tracking fields and low_stock_threshold
  - Menu items have cost_to_make for profitability analysis

- **MerchandiseCollection**: Merchandise collection management
  - Belongs to restaurant
  - Has many merchandise_items
  - Contains name, description, and active status
  - Restaurants can have multiple collections with one set as active via current_merchandise_collection_id

- **MerchandiseItem**: Merchandise item management
  - Belongs to merchandise_collection
  - Belongs to merchandise_category (optional)
  - Has many merchandise_variants (for size/color options)
  - Contains name, description, base_price, and multiple image URLs
  - Includes stock_status tracking (in_stock, low_stock, out_of_stock)
  - Has configurable low_stock_threshold
  - Uses S3 for image storage with unique filenames
  - Has many merchandise_stock_audits for inventory tracking

- **MerchandiseVariant**: Merchandise variants
  - Belongs to merchandise_item
  - Contains variation info like size, color, etc.
  - Has its own price that can differ from the base price

- **Layout/SeatSection/Seat**: Table layout configuration
  - All belong to restaurant through associations
  - Used for visualizing and managing the physical space

- **Notification**: Notification records
  - Belongs to a notifiable object (polymorphic)
  - Tracks notification type, delivery method, and status
  - Includes recipient information and message content

- **NotificationTemplate**: Customizable notification templates
  - Belongs to restaurant
  - Contains template content and variables
  - Used for generating consistent notifications

---

## **Notification System**

The system includes a robust notification framework for communicating with customers:

### 1. Notification Channels

- **Email** - Using SendGrid for transactional emails
- **SMS** - Using ClickSend for text messages
- **WhatsApp** - Using Wassenger for WhatsApp messages

Each restaurant can configure which notification channels they want to use for different types of communications:

```ruby
# In Restaurant model (admin_settings JSONB field)
{
  "notification_channels": {
    "orders": {
      "email": true,
      "sms": true
    },
    "reservations": {
      "email": true,
      "sms": false
    }
  }
}
```

The system sends notifications by default unless explicitly disabled, ensuring backward compatibility with existing restaurants that don't have notification preferences set yet.

### 2. Background Processing

Notifications are processed asynchronously using Sidekiq:

```ruby
# app/jobs/send_sms_job.rb
class SendSmsJob < ApplicationJob
  queue_as :notifications

  def perform(phone_number, message)
    client = ClicksendClient.new
    client.send_sms(phone_number, message)
  end
end

# app/jobs/send_whatsapp_job.rb
class SendWhatsappJob < ApplicationJob
  queue_as :notifications

  def perform(phone_number, message)
    client = WassengerClient.new
    client.send_message(phone_number, message)
  end
end
```

### 3. Mailers

Email notifications are handled through dedicated mailers:

```ruby
# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  def order_confirmation(order)
    @order = order
    mail(to: @order.contact_email, subject: "Your order has been confirmed")
  end

  def order_preparing(order)
    @order = order
    mail(to: @order.contact_email, subject: "Your order is being prepared")
  end

  def order_ready(order)
    @order = order
    mail(to: @order.contact_email, subject: "Your order is ready for pickup")
  end
end

# app/mailers/reservation_mailer.rb
class ReservationMailer < ApplicationMailer
  def reservation_confirmation(reservation)
    @reservation = reservation
    mail(to: @reservation.contact_email, subject: "Your reservation is confirmed")
  end
end
```

### 4. Notification Tracking

The Notification model tracks all sent notifications:

```ruby
# app/models/notification.rb
class Notification < ApplicationRecord
  belongs_to :notifiable, polymorphic: true
  
  enum status: { pending: 'pending', sent: 'sent', failed: 'failed' }
  enum notification_type: { confirmation: 'confirmation', reminder: 'reminder', update: 'update' }
  enum delivery_method: { email: 'email', sms: 'sms', whatsapp: 'whatsapp' }
  
  # Enhanced with additional fields for better tracking
  attribute :recipient_info, :jsonb, default: {}
  attribute :message_content, :text
  attribute :error_details, :jsonb, default: {}
end
```

---

## **Environment Variables**

### Core Configuration

- **Database**:
  - `DATABASE_URL` – PostgreSQL connection string
- **Redis / Sidekiq**:
  - `REDIS_URL` – Redis connection string
- **Rails**:
  - `RAILS_ENV` – Environment (development/production)
  - `SECRET_KEY_BASE` – For secure cookies and JWT encoding
  - `DEFAULT_RESTAURANT_ID` – Default restaurant ID for public pages

### External Services

- **ClickSend** (SMS):
  - `CLICKSEND_USERNAME`
  - `CLICKSEND_API_KEY`
  - `CLICKSEND_APPROVED_SENDER_ID`
- **SendGrid** (Emails):
  - `SENDGRID_USERNAME`
  - `SENDGRID_API_KEY`
- **Wassenger** (WhatsApp):
  - `WASSENGER_API_KEY`
  - `WASSENGER_GROUP_ID` 
- **AWS S3**:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`
  - `S3_BUCKET_NAME`
- **PayPal**:
  - `PAYPAL_CLIENT_ID`
  - `PAYPAL_CLIENT_SECRET`
  - `PAYPAL_MODE` (sandbox/live)
- **Stripe**:
  - `STRIPE_SECRET_KEY`
  - `STRIPE_PUBLISHABLE_KEY`
  - `STRIPE_WEBHOOK_SECRET`

---

## **Local Development Setup**

1. **Clone the Repository**  
   ```bash
   git clone https://github.com/YourUsername/hafaloha-backend.git
   cd hafaloha-backend
   ```

2. **Install Ruby Gems**  
   ```bash
   bundle install
   ```

3. **Install and Start PostgreSQL** (macOS example using Homebrew)  
   ```bash
   brew install postgresql
   brew services start postgresql
   ```

4. **Create and Migrate the Database**  
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed # Optional: Seed initial data
   ```

5. **Install and Start Redis** (for Sidekiq)  
   ```bash
   brew install redis
   brew services start redis
   ```

6. **Run Sidekiq** in a Separate Terminal  
   ```bash
   bundle exec sidekiq -C config/sidekiq.yml
   ```

7. **Start Rails Server**  
   ```bash
   rails server
   ```
   By default, Rails listens on `http://localhost:3000`.

8. **Create a Test Restaurant and Admin**
   ```bash
   rails console
   ```
   ```ruby
   # Create a restaurant with allowed origins
   restaurant = Restaurant.create!(
     name: "Test Restaurant",
     address: "123 Test St",
     time_zone: "Pacific/Guam",
     allowed_origins: ["http://localhost:5173"]
   )
   
   # Create an admin user
   User.create!(
     email: "admin@example.com",
     password: "password",
     role: "admin",
     restaurant: restaurant
   )
   ```

---

## **API Endpoints**

The API is organized into several main groups:

### Authentication
- `POST /signup` - Create a new user account
- `POST /login` - Get JWT token
- `POST /verify_phone` - Verify phone number with code
- `POST /resend_code` - Resend verification code

### Reservations
- `GET /reservations` - List reservations
- `POST /reservations` - Create reservation
- `GET /reservations/:id` - Get reservation details
- `PATCH /reservations/:id` - Update reservation
- `DELETE /reservations/:id` - Cancel reservation

### Orders
- `GET /orders` - List orders (paginated)
- `POST /orders` - Create order
- `GET /orders/:id` - Get order details
- `PATCH /orders/:id` - Update order status
- `DELETE /orders/:id` - Cancel order
- `GET /orders/unacknowledged` - Get orders not yet acknowledged by current user
- `POST /orders/:id/acknowledge` - Mark an order as acknowledged by current user

### Payments
- `POST /payments/process` - Process a payment
- `GET /order_payments` - List payment history
- `POST /order_payments` - Create additional payment
- `POST /order_payments/:id/refund` - Process refund
- `GET /store_credits` - Get store credit balance
- `POST /store_credits/add` - Add store credit
- `POST /store_credits/use` - Use store credit

### Merchandise
- `GET /merchandise_collections` - List merchandise collections
- `POST /merchandise_collections` - Create new merchandise collection
- `GET /merchandise_collections/:id` - Get specific collection details
- `PATCH /merchandise_collections/:id` - Update collection details
- `DELETE /merchandise_collections/:id` - Delete a collection
- `PATCH /merchandise_collections/:id/activate` - Set a collection as the active one

- `GET /merchandise_items` - List merchandise items (with optional collection_id filter)
- `POST /merchandise_items` - Create new merchandise item (with image upload)
- `GET /merchandise_items/:id` - Get specific item details
- `PATCH /merchandise_items/:id` - Update item details (with image upload)
- `DELETE /merchandise_items/:id` - Delete an item

- `GET /merchandise_variants` - List merchandise variants
- `POST /merchandise_variants` - Create new merchandise variant
- `GET /merchandise_variants/:id` - Get specific variant details
- `PATCH /merchandise_variants/:id` - Update variant details
- `DELETE /merchandise_variants/:id` - Delete a variant

### Performance Optimizations

The API includes several performance optimizations to handle high traffic loads:

#### 1. Database Optimizations

- **Performance Indexes**: Critical indexes on frequently queried columns:
  ```ruby
  # Example from migration
  add_index :orders, [:restaurant_id, :status, :created_at], name: 'index_orders_on_restaurant_status_date'
  add_index :orders, [:user_id, :created_at], name: 'index_orders_on_user_created_at'
  ```

- **Connection Pooling**: Configurable database connection pool:
  ```ruby
  # In database.yml
  production:
    pool: <%= ENV.fetch("DB_POOL_SIZE", 30) %>
  ```

- **Redis Caching**: Redis-backed cache store with memory fallback:
  ```ruby
  # In production.rb
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" },
    error_handler: -> (method:, returning:, exception:) {
      Rails.logger.error "Redis error: #{exception.message}"
    }
  }
  ```

#### 2. Pagination

The API uses efficient pagination for list endpoints to ensure optimal performance with large datasets:

```ruby
# Example pagination implementation in OrdersController
def index
  # Get total count before pagination
  total_count = @orders.count
  
  # Apply sorting and pagination
  @orders = @orders.order(created_at: :desc)
                  .offset((page - 1) * per_page)
                  .limit(per_page)
  
  render json: {
    orders: @orders,
    total_count: total_count,
    page: page,
    per_page: per_page
  }, status: :ok
end
```

Paginated endpoints return a consistent response format:
```json
{
  "orders": [...],
  "total_count": 42,
  "page": 1,
  "per_page": 10
}
```

### Menus
- `GET /menus` - List menus
- `GET /menus/:id` - Get specific menu with items
- `GET /menu_items` - List menu items
- `GET /menu_items/:id` - Get menu item details

### Admin
- `GET /admin/analytics/*` - Various analytics endpoints
- `GET /admin/restaurant/allowed_origins` - Get allowed CORS origins
- `POST /admin/restaurant/allowed_origins` - Update allowed CORS origins
- `GET /admin/site_settings` - Get site-wide settings
- `PATCH /admin/site_settings` - Update site-wide settings

### VIP Access
- `GET /vip/codes` - List VIP access codes
- `POST /vip/codes/individual` - Generate individual VIP codes
- `POST /vip/codes/group` - Generate a group VIP code
- `PATCH /vip/codes/:id` - Update VIP code details
- `POST /vip/codes/:id/deactivate` - Deactivate a VIP code
- `POST /vip/codes/:id/reactivate` - Reactivate a VIP code
- `POST /vip/codes/:id/archive` - Archive a VIP code
- `POST /vip/codes/:id/unarchive` - Unarchive a VIP code
- `GET /vip/codes/:id/usage` - Get usage statistics for a VIP code
- `POST /vip/validate` - Validate a VIP code without using it
- `POST /vip/use` - Validate and mark a VIP code as used
- `POST /vip/codes/send` - Send existing VIP codes via email
- `POST /vip/codes/bulk_send` - Generate and send new VIP codes via email
- `PATCH /restaurants/:id/toggle_vip_mode` - Enable/disable VIP-only checkout mode

For detailed documentation on the VIP Code System, see [VIP Code System Documentation](docs/vip_code_system.md).

### Inventory Management
- `PATCH /menu_items/:id` - Update menu item inventory settings
- `POST /menu_items/:id/mark_damaged` - Record damaged items
- `POST /menu_items/:id/update_stock` - Update stock quantity
- `GET /menu_items/:id/stock_audits` - Get stock audit history
- `POST /menu_items/bulk_update` - Update multiple items at once

For detailed documentation on the Inventory Management System, see [Inventory Tracking System Documentation](docs/inventory_tracking_system.md).

### Restaurant Scope
All endpoints automatically filter data by the restaurant context from:
1. The JWT token's `restaurant_id` claim
2. The `restaurant_id` parameter (for super admins)
3. Public endpoints that don't require restaurant context

---

## **Production Deployment**

### Render.com Setup

1. **Create a Web Service** for the Rails app:
   - **Build Command**: `bundle install && bundle exec rails db:migrate`
   - **Start Command**: `bundle exec rails server -p 3001`
   - **Environment Variables**: Add all required ones from above

2. **Create a Background Worker** for Sidekiq:
   - **Build Command**: `bundle install`
   - **Start Command**: `bundle exec sidekiq -C config/sidekiq.yml`
   - **Environment Variables**: Same as the web service

3. **Create Redis and PostgreSQL Services**
   - Link them to your web and worker services

4. **Configure S3 Bucket**
   - Create a bucket for image uploads
   - Set up CORS for the bucket
   - Create an IAM user with appropriate permissions

5. **Set Up External Services**
   - SendGrid for email
   - ClickSend for SMS
   - Wassenger for WhatsApp (if needed)
   - PayPal and Stripe for payment processing

---

## **Testing**

The project uses RSpec for testing. Run the test suite with:

```bash
bundle exec rspec
```

### RSpec Configuration

The test suite is configured with:

- **Progress Format**: Shows green dots for passing tests (configure in `.rspec`)
- **Documentation Format**: Use `--format documentation` in `.rspec` for detailed output
- **Fixture Paths**: Uses array-based fixture paths for Rails 7.1 compatibility
- **Factory Bot**: Integration for easy test data creation
- **Controller Specs**: Helper methods for authentication and authorization testing

### Running Specific Tests

Run specific test files:

```bash
bundle exec rspec spec/models/user_spec.rb
```

Run specific test groups:

```bash
bundle exec rspec spec/controllers/
```

Run tests with specific tags:

```bash
bundle exec rspec --tag focus
```

---

## **Database Schema**

The database includes these key tables:

- `restaurants` - Central tenant table
- `site_settings` - Site-wide settings for each restaurant
- `users` - Authentication and roles
- `reservations` - Table bookings
- `orders` - Food orders
- `order_payments` - Payment history for orders
- `store_credits` - Customer account balances
- `menus`/`menu_items`/`categories` - Menu structure
- `menu_item_stock_audits` - Inventory tracking for menu items
- `merchandise_collections`/`merchandise_items`/`merchandise_variants` - Merchandise structure
- `merchandise_categories` - Categories for merchandise items
- `merchandise_stock_audits` - Inventory tracking for merchandise
- `layouts`/`seat_sections`/`seats` - Physical layout
- `option_groups`/`options` - Menu item customization
- `promo_codes` - Discount codes
- `operating_hours` - Restaurant opening times
- `special_events` - Special bookings or closed days
- `notifications` - Notification tracking
- `notification_templates` - Customizable notification templates

---

## **Code Organization**

The codebase is organized following Rails conventions with some additional structure:

1. **Controllers** - Handle API requests and responses
   - `app/controllers/concerns` - Shared controller functionality
   - `app/controllers/admin` - Admin-specific endpoints

2. **Models** - Database models and business logic
   - `app/models/concerns` - Shared model functionality

3. **Services** - External service integrations
   - `app/services/clicksend_client.rb` - SMS integration
   - `app/services/wassenger_client.rb` - WhatsApp integration
   - `app/services/s3_uploader.rb` - AWS S3 integration

4. **Mailers** - Email templates and sending logic
   - `app/mailers/order_mailer.rb` - Order-related emails
   - `app/mailers/reservation_mailer.rb` - Reservation-related emails
   - `app/mailers/password_mailer.rb` - Password reset emails
   - `app/mailers/vip_code_mailer.rb` - VIP code emails
   - `app/mailers/generic_mailer.rb` - Custom emails from templates

5. **Jobs** - Background processing
   - `app/jobs/send_sms_job.rb` - Asynchronous SMS sending
   - `app/jobs/send_whatsapp_job.rb` - Asynchronous WhatsApp messaging
   - `app/jobs/send_vip_codes_batch_job.rb` - Batch processing for VIP codes

---

## **Contact & Support**

If you have questions about:

- **Architecture** (multi-tenant design, reservations, ordering)
- **Messaging logic** (SMS/WhatsApp/Email)
- **Sidekiq background jobs**
- **Payment processing** (PayPal/Stripe)

Please check the inline code comments or contact the dev team.

---

## **Schema Verification System**

To ensure database schema consistency between the application's schema.rb file and the actual database structure, we've implemented a comprehensive schema verification system. For detailed information, see:

- [Schema Verification System Documentation](docs/schema_verification_system.md)
- [Migration Best Practices](docs/migration_best_practices.md)
- [Schema Fix Instructions](docs/schema_fix_instructions.md)

---

**Hafaloha - Your Restaurant Management SaaS Platform**
