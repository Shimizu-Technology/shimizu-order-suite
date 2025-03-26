module Admin
  # Base controller for all admin-related controllers
  # This controller provides common functionality and authorization checks
  # for the admin section of the application.
  #
  # It uses Pundit to authorize access to admin features based on user roles.
  # Both admin and staff users can access admin routes, but staff users
  # have limited permissions compared to admin users.
  class BaseController < ApplicationController
    include Pundit::Authorization
    
    before_action :authorize_admin
    
    private
    
    # Authorize access to admin features
    # This method uses the AdminPolicy to check if the current user
    # has permission to access admin features.
    #
    # The AdminPolicy allows both admin and staff users to access
    # admin features, but restricts certain actions (create, update, destroy)
    # to admin users only.
    def authorize_admin
      authorize :admin, :index?
    end
  end
end
