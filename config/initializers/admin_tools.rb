# frozen_string_literal: true

# admin_tool blocks in views render only for users with admin access.
# User#admin? comes from the access_level enum and is false for super
# admins and owners, so check admin_access? instead.
AdminTools.configure do |config|
  config.admin_method = :admin_access?
end
