# app/services/analytics_service.rb
class AnalyticsService
  def initialize(user = nil, restaurant = nil)
    @user = user
    @restaurant = restaurant
  end

  # Track events with proper restaurant context
  def track(event_name, properties = {})
    return unless enabled?
    
    # Skip tracking for system events when no user is present
    return if @user.nil? && !system_event?(event_name)

    # Add restaurant context if available
    props_with_context = properties.dup
    
    if @restaurant.present?
      # Add restaurant as a group to enable cross-restaurant analytics
      props_with_context[:groups] = { restaurant: @restaurant.id.to_s }
      
      # Add restaurant properties
      props_with_context[:restaurant_id] = @restaurant.id
      props_with_context[:restaurant_name] = @restaurant.name
    end
    
    # Add user context if available
    distinct_id = @user&.id&.to_s || 'anonymous'
    
    # Capture the event
    POSTHOG_CLIENT.capture({
      distinct_id: distinct_id,
      event: event_name,
      properties: props_with_context
    })
  end

  # Identify a user with their properties
  def identify(properties = {})
    return unless enabled? && @user.present?
    
    # Set user properties
    user_properties = {
      email: @user.email,
      name: @user.name || "#{@user.first_name} #{@user.last_name}".strip,
      role: @user.role,
      created_at: @user.created_at
    }.merge(properties)
    
    # Identify the user
    POSTHOG_CLIENT.identify({
      distinct_id: @user.id.to_s,
      properties: user_properties
    })
  end

  # Group identify for restaurant properties
  def group_identify(properties = {})
    return unless enabled? && @restaurant.present?
    
    # Set restaurant properties
    restaurant_properties = {
      name: @restaurant.name,
      created_at: @restaurant.created_at
    }.merge(properties)
    
    # Identify the restaurant group
    POSTHOG_CLIENT.group_identify({
      group_type: 'restaurant',
      group_key: @restaurant.id.to_s,
      properties: restaurant_properties
    })
  end

  private
  
  def enabled?
    ENV['POSTHOG_API_KEY'].present?
  end
  
  def system_event?(event_name)
    event_name.start_with?('system.')
  end
end
