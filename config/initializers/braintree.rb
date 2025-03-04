# config/initializers/braintree.rb

# This initializer sets up the Braintree configuration.
# We don't initialize it here because we'll create a gateway per restaurant.
# This is just to ensure the Braintree module is loaded.

require 'braintree'
