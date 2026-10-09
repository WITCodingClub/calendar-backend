# frozen_string_literal: true

# Old paths of the JWT API that published extension builds still call. Each
# one runs the same action as its new path. Api::LegacyRouteCounting counts the
# requests in calendar_api_legacy_requests_total, by path. Remove a path when
# its count stays at zero after the extension release that stops calling it.
#
# This file is drawn inside namespace :api in config/routes/api.rb, before the
# catch-all route. Add an old path like this:
#
#   get "user/email", to: "profiles#email", defaults: { legacy_route: "GET user/email" }
#
# No old path is in use now.
