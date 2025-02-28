# **Hafaloha Backend (Rails API)**

A multi-tenant SaaS platform for restaurant reservation and order management.

## **Overview**

Hafaloha is a SaaS (Software as a Service) platform that enables multiple restaurants to:

- Manage **reservations** and table layouts
- Take **food orders** online
- Send **notifications** via multiple channels
- Track **inventory** and **menu items**
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

### Data Flow

1. **API Requests** come in through controllers
2. **Restaurant Context** is automatically applied based on JWT or params
3. **Database Queries** are automatically filtered by restaurant
4. **Background Jobs** process notifications asynchronously
5. **CORS Configuration** allows specific frontend origins per restaurant

---

## **Multi-tenant Architecture**

Hafaloha uses a multi-tenant architecture where all restaurants share the same database, but data is isolated through application-level controls. This provides efficient resource utilization while ensuring proper data separation.

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
  - Has many users, menus, layouts, reservations, orders
  - Stores configuration including allowed CORS origins
  - Contains basic information like name, address, phone number, time zone

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

- **Menu/MenuItem/Category**: Menu management
  - All belong to restaurant directly or through associations
  - Menu items can have option groups and options

- **Layout/SeatSection/Seat**: Table layout configuration
  - All belong to restaurant through associations
  - Used for visualizing and managing the physical space

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
- `GET /orders` - List orders
- `POST /orders` - Create order
- `GET /orders/:id` - Get order details
- `PATCH /orders/:id` - Update order status
- `DELETE /orders/:id` - Cancel order

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

---

## **Testing**

Run the test suite with:

```bash
rails test
```

Or with RSpec (if configured):

```bash
bundle exec rspec
```

---

## **Database Schema**

The database includes these key tables:

- `restaurants` - Central tenant table
- `site_settings` - Site-wide settings for each restaurant
- `users` - Authentication and roles
- `reservations` - Table bookings
- `orders` - Food orders
- `menus`/`menu_items`/`categories` - Menu structure
- `layouts`/`seat_sections`/`seats` - Physical layout
- `option_groups`/`options` - Menu item customization
- `promo_codes` - Discount codes
- `operating_hours` - Restaurant opening times
- `special_events` - Special bookings or closed days

---

## **Contact & Support**

If you have questions about:

- **Architecture** (multi-tenant design, reservations, ordering)
- **Messaging logic** (SMS/WhatsApp/Email)
- **Sidekiq background jobs**

Please check the inline code comments or contact the dev team.

---

**Hafaloha - Your Restaurant Management SaaS Platform**
