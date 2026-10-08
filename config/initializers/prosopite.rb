# frozen_string_literal: true

# Prosopite finds N+1 queries (#654). The gem is in the development and test
# groups only, so production never loads it and this file does nothing there.
#
# The Rack middleware scans each request. It does not scan jobs, specs outside
# a request, or rake tasks. To scan other code, wrap it in Prosopite.scan { }.
#
# Development writes each N+1 to the Rails log and to log/prosopite.log.
# Test raises Prosopite::NPlusOneQueriesError, so a request spec fails when
# the request sends an N+1.
if defined?(Prosopite)
  require "prosopite/middleware/rack"
  Rails.application.config.middleware.use(Prosopite::Middleware::Rack)

  Rails.application.config.after_initialize do
    Prosopite.rails_logger = true
    Prosopite.prosopite_logger = Rails.env.development?
    Prosopite.raise = Rails.env.test?

    # Queries that gems send on their own admin pages. The app cannot preload them.
    Prosopite.ignore_queries = [ /"(console1984|audits1984)_/ ]
  end
end
