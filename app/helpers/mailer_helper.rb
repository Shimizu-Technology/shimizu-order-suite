# app/helpers/mailer_helper.rb
# This file exists for compatibility - all methods are now in app/mailers/concerns/mailer_helper.rb

# Include the actual implementation from the concerns directory
require_relative '../mailers/concerns/mailer_helper'

# Re-open the module to ensure it's available in the helpers namespace
module MailerHelper
  # All methods are now defined in app/mailers/concerns/mailer_helper.rb
  # This empty module just includes the actual implementation
end
