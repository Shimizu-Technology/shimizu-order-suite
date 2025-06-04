# Slug-Based Fundraiser URLs

## Overview

The Hafaloha Wholesale Fundraising system now uses slug-based URLs for improved SEO and user experience. This document outlines the backend implementation details, API endpoints, and authentication considerations for developers.

## Model Configuration

### Fundraiser Model

The `Fundraiser` model includes slug-related validations and callbacks:

```ruby
class Fundraiser < ApplicationRecord
  # Validations
  validates :slug, presence: true, uniqueness: { scope: :restaurant_id }, 
            format: { with: /\A[a-z0-9\-_]+\z/, message: "only allows lowercase letters, numbers, hyphens, and underscores" }
  
  # Callbacks
  before_validation :normalize_slug
  
  private
  
  # Convert slug to lowercase and replace spaces with hyphens
  def normalize_slug
    self.slug = slug.to_s.downcase.gsub(/\s+/, '-') if slug.present?
  end
end
```

Key features:
- Slug presence is required
- Slugs must be unique within a restaurant context
- Format validation ensures slugs only contain lowercase letters, numbers, hyphens, and underscores
- `normalize_slug` callback ensures consistent formatting

## API Endpoints

### Slug-Based Fundraiser Retrieval

```ruby
# In Api::Wholesale::FundraisersController
def by_slug
  @fundraiser = Fundraiser.find_by!(slug: params[:slug], restaurant: current_restaurant)
  authorize @fundraiser
  render json: @fundraiser
end
```

### Authentication Configuration

The controller uses optional authentication for publicly accessible fundraiser endpoints:

```ruby
# In Api::Wholesale::FundraisersController
class Api::Wholesale::FundraisersController < ApiController
  skip_before_action :authenticate_user!, only: [:index, :show, :by_slug]
  before_action :authenticate_user_if_token_present, only: [:index, :show, :by_slug]
  # ...
end
```

### Authorization Policy

The `FundraiserPolicy` includes specific authorization for slug-based access:

```ruby
# In FundraiserPolicy
def by_slug?
  show? # Uses the same authorization rules as the show action
end
```

## Tenant Isolation

Slug uniqueness is scoped to `restaurant_id` to ensure:
1. Different restaurants can use the same slug
2. Slugs within a restaurant are unique
3. Tenant isolation is maintained for security

## API Usage Examples

### Fetch Fundraiser by Slug

```javascript
// Frontend API call
const getFundraiserBySlug = async (slug) => {
  const response = await axios.get(`${config.apiBaseUrl}/api/wholesale/fundraisers/by_slug/${slug}`, { 
    headers: getHeaders() 
  });
  return response.data;
};
```

## Error Handling

1. When a slug doesn't exist, the API returns a 404 Not Found error
2. If a user doesn't have permission, the API returns a 403 Forbidden error
3. Frontend components should handle these errors gracefully

## Best Practices

1. **Tenant Isolation**: Always verify tenant context when looking up by slug
2. **Authorization**: Ensure proper authorization checks are in place
3. **Validation**: Validate slug format before saving
4. **Performance**: Consider adding database indexes for slug lookups if needed
