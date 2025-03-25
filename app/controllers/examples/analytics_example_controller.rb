# app/controllers/examples/analytics_example_controller.rb
module Examples
  class AnalyticsExampleController < ApplicationController
    # This is an example controller demonstrating how to use the AnalyticsService
    # in the Hafaloha application. This controller is for demonstration purposes only
    # and is not meant to be used in production.
    
    # This controller is for demonstration purposes only
    # No authentication is required for these example endpoints
    
    # GET /examples/analytics
    def index
      render json: {
        message: "Analytics Example Controller",
        available_endpoints: [
          { method: "GET", path: "/examples/analytics/track_event", description: "Track a sample event" },
          { method: "GET", path: "/examples/analytics/identify_user", description: "Identify a sample user" },
          { method: "GET", path: "/examples/analytics/group_identify", description: "Identify a sample restaurant group" }
        ]
      }
    end
    
    # GET /examples/analytics/track_event
    def track_event
      # Create a sample analytics service instance
      # In a real controller, you would use the analytics method from ApplicationController
      sample_analytics = AnalyticsService.new(current_user, @current_restaurant)
      
      # Track a sample event
      sample_analytics.track('example.event', {
        example_property: 'example value',
        timestamp: Time.current.iso8601
      })
      
      render json: {
        message: "Sample event tracked successfully",
        event_name: 'example.event',
        properties: {
          example_property: 'example value',
          timestamp: Time.current.iso8601
        }
      }
    end
    
    # GET /examples/analytics/identify_user
    def identify_user
      # Create a sample user for demonstration
      sample_user = User.new(
        id: 999999,
        email: 'example@example.com',
        first_name: 'Example',
        last_name: 'User',
        role: 'customer'
      )
      
      # Create a sample analytics service instance with the sample user
      sample_analytics = AnalyticsService.new(sample_user, @current_restaurant)
      
      # Identify the sample user
      sample_analytics.identify({
        example_property: 'example value'
      })
      
      render json: {
        message: "Sample user identified successfully",
        user: {
          id: sample_user.id,
          email: sample_user.email,
          name: "#{sample_user.first_name} #{sample_user.last_name}",
          role: sample_user.role
        }
      }
    end
    
    # GET /examples/analytics/group_identify
    def group_identify
      # Create a sample restaurant for demonstration
      sample_restaurant = Restaurant.new(
        id: 999999,
        name: 'Example Restaurant',
        address: '123 Example St',
        time_zone: 'Pacific/Guam'
      )
      
      # Create a sample analytics service instance with the sample restaurant
      sample_analytics = AnalyticsService.new(current_user, sample_restaurant)
      
      # Identify the sample restaurant group
      sample_analytics.group_identify({
        example_property: 'example value'
      })
      
      render json: {
        message: "Sample restaurant group identified successfully",
        restaurant: {
          id: sample_restaurant.id,
          name: sample_restaurant.name,
          address: sample_restaurant.address,
          time_zone: sample_restaurant.time_zone
        }
      }
    end
    
    private
    
    # Override the skip_tracking? method to ensure tracking for this example controller
    def skip_tracking?
      false
    end
  end
end
