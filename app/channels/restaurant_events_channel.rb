class RestaurantEventsChannel < ApplicationCable::Channel
  def subscribed
    # Ensure the user has access to this restaurant
    restaurant_id = params[:restaurant_id]
    if current_user && 
       (current_user.restaurant_id == restaurant_id || 
        current_user.role == 'super_admin')
      stream_from "restaurant_events_#{restaurant_id}"
    else
      reject
    end
  end

  def unsubscribed
    # Any cleanup needed
  end
end
