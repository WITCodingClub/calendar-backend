source "https://rubygems.org"

# Version rule: pin each gem to the major version we run with "~> X.Y".
# For a 0.x gem, a minor bump can break, so pin it with "~> 0.Y.Z".
# Rails is pinned to its minor version, because each Rails minor upgrade needs app changes.

gem "rails", "~> 8.1.4"
gem "propshaft", "~> 1.3"
gem "pg", "~> 1.6"
# Catches unsafe schema migrations before they lock production tables
gem "strong_migrations", "~> 2.8"
gem "puma", "~> 8.0"
gem "importmap-rails", "~> 2.2"
gem "tailwindcss-rails", "~> 4.6"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"

# Renders the public API reference from the markdown file in docs/
gem "redcarpet", "~> 3.6"
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Database-backed adapters for cache and jobs
gem "solid_cache", "~> 1.0"
gem "solid_queue", "~> 1.7"
gem "mission_control-jobs", "~> 1.3"

# Admin tooling
gem "flipper", "~> 1.4"
gem "flipper-active_record", "~> 1.4"
gem "flipper-ui", "~> 1.4"
gem "flipper-active_support_cache_store", "~> 1.4"
gem "blazer", "~> 3.5"
gem "pghero", "~> 4.0"
gem "audits1984", "~> 0.1.7"
gem "console1984", "~> 0.2.4"

gem "bootsnap", "~> 1.26", require: false
gem "thruster", "~> 0.1.26", require: false

# Authentication
gem "devise", "~> 5.0"

# Passkeys (WebAuthn) for quick extension sign-in on a new device
gem "webauthn", "~> 3.4"

# Google OAuth + Calendar API
gem "omniauth-google-oauth2", "~> 1.2"
gem "omniauth-entra-id", "~> 3.1"
gem "omniauth-rails_csrf_protection", "~> 2.0"
gem "google-apis-calendar_v3", "~> 0.57.0"
gem "googleauth", "~> 1.17"

# Authorization
gem "pundit", "~> 2.5"

# Admin-only blocks in views (admin_tool)
gem "admin_tools", "~> 1.0"

# Recurrence rules (for Google Calendar event sync)
gem "ice_cube", "~> 0.17.0"

# ICS calendar feed generation
gem "icalendar", "~> 2.12"

# Encoded/hashid public IDs
gem "encoded_ids", "~> 1.1"

# Rate limiting / CORS
gem "rack-attack", "~> 6.8"
gem "rack-cors", "~> 3.0"

# Public catalog GraphQL API
gem "graphql", "~> 2.6"

# Liquid templating for calendar event title/description customization
gem "liquid", "~> 5.14"

# HTML entity decoding (for ICS feed content and course titles)
gem "htmlentities", "~> 4.4"

# HTTP client (for LeopardWeb, RMP, faculty directory scraping)
gem "faraday", "~> 2.14"
gem "faraday-retry", "~> 2.4"

# JWT for OAuth state signing and RISC webhook validation
gem "jwt", "~> 3.3"

# Vector search over course, instructor and review embeddings (docs/embeddings.md)
gem "neighbor", "~> 1.2"

# Pagination
gem "kaminari", "~> 1.2"

# Server uptime monitoring
gem "okcomputer", "~> 1.20"

# Prometheus metrics for Grafana (docs/metrics.md)
gem "yabeda-rails", "~> 0.11.0"
gem "yabeda-puma-plugin", "~> 0.9.0"
gem "yabeda-activejob", "~> 0.6.0"
gem "yabeda-prometheus", "~> 0.9.1"
# prometheus-client 4.x reads labels back from its multi-process file store
# with CGI.parse, which Ruby 4.0 removed. prometheus-client 5 does not need it,
# but yabeda-prometheus 0.9 allows only 4.x. Remove this when that changes.
gem "cgi", "~> 0.5.2"

group :development, :test do
  gem "debug", "~> 1.11", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", "~> 0.9.3", require: false
  # No version cap: CI runs Brakeman with --ensure-latest, so it must stay current.
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", "~> 1.1", require: false
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.5"
  gem "faker", "~> 3.8"
  gem "dotenv-rails", "~> 3.2"

  # N+1 query detection (#654). Prosopite needs pg_query to fingerprint
  # PostgreSQL queries. See config/initializers/prosopite.rb.
  gem "prosopite", "~> 2.2"
  gem "pg_query", "~> 6.2"
end

group :development do
  gem "web-console", "~> 4.3"
  gem "letter_opener", "~> 1.10"
  gem "letter_opener_web", "~> 3.0"
  gem "annotaterb", "~> 4.25"
end

group :test do
  gem "shoulda-matchers", "~> 8.0"
  gem "simplecov", "~> 1.3", require: false
  gem "webmock", "~> 3.26"
end
