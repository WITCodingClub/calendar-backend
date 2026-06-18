source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "tailwindcss-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "bcrypt", "~> 3.1.7"
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Database-backed adapters for cache, jobs, and cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "mission_control-jobs"

# Admin tooling
gem "flipper"
gem "flipper-active_record"
gem "flipper-ui"
gem "flipper-active_support_cache_store"
gem "blazer"
gem "pghero"
gem "audits1984"
gem "console1984"

gem "bootsnap", require: false
gem "thruster", require: false
gem "image_processing", "~> 2.0"
gem "ruby-vips"

# Authentication
gem "devise", "~> 5.0"

# Google OAuth + Calendar API
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "google-apis-calendar_v3"
gem "googleauth"
gem "multi_json"

# Authorization
gem "pundit"

# Recurrence rules (for Google Calendar event sync)
gem "ice_cube"

# ICS calendar feed generation
gem "icalendar"

# Encoded/hashid public IDs
gem "encoded_ids"

# Rate limiting / CORS
gem "rack-attack"
gem "rack-cors"

# Liquid templating for calendar event title/description customization
gem "liquid"

# HTML entity decoding (for ICS feed content and course titles)
gem "htmlentities"

# HTTP client (for LeopardWeb, RMP, faculty directory scraping)
gem "faraday"
gem "faraday-retry"

# JWT for OAuth state signing and RISC webhook validation
gem "jwt"

# Pagination
gem "kaminari"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "web-console"
  gem "letter_opener"
  gem "letter_opener_web", "~> 3.0"
  gem "annotaterb"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "shoulda-matchers"
end
