# frozen_string_literal: true

source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem "tzinfo-data", platforms: %i[windows jruby]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
# gem "solid_cache"  # Disabled - using Redis for caching instead
gem "solid_queue"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

gem "pundit"
gem "jwt"
gem "rack-cors"
gem "pg", "~> 1.6.2"
gem "redis", "~> 5.0"
gem "redis-session-store"
gem "rack-attack"
gem "lockbox"
gem "blind_index"
gem "invisible_captcha"
gem "paper_trail"
gem "audits1984"
gem "console1984"
gem "acts_as_paranoid"
gem "pg_search"
gem "hashid-rails"
gem "friendly_id"
gem "aasm"
gem "okcomputer"
gem "ahoy_matey"
gem "ahoy_email"
gem "blazer"
gem "statsd-instrument"
gem "rails_performance"
gem "premailer-rails"
gem "email_reply_parser"
gem "mailkick"
gem "mission_control-jobs"
gem "browser"
gem "strong_migrations"
gem "tailwindcss-rails"
gem "flipper"
gem "flipper-active_record"
gem "flipper-ui"
gem "flipper-active_support_cache_store"
gem "dotenv-rails"
gem "liquid"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  gem "relaxed-rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-factory_bot", require: false
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "pundit-matchers"
  gem "rubocop-capybara", "~> 2.22", ">= 2.22.1"
  gem "rubocop-rspec", "~> 3.8"
  gem "rubocop-rspec_rails", "~> 2.32"
  gem "query_count"
  gem 'prosopite'
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  gem "actual_db_schema"
  gem "annotaterb"
  gem "listen", "~> 3.9"
  gem "letter_opener_web"
  gem "foreman"
  gem "awesome_print"
  gem "rack-mini-profiler", "~> 3.3", require: false
  gem "stackprof"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "rspec-openapi", "~> 0.20"
  gem 'simplecov', require: false
end

gem "faraday", "~> 2.14"

gem "tailwindcss-ruby", "~> 4.1"
gem "icalendar", "~> 2.12", ">= 2.12.1"

gem "google-apis-calendar_v3", "~> 0.51.0"
gem "googleauth", "~> 1.16"

gem "omniauth", "~> 2.1", ">= 2.1.4"
gem "omniauth-google-oauth2", "~> 1.2", ">= 1.2.1"

gem "pgvector"
gem "neighbor"
gem "log_bench"

gem "kaminari", "~> 1.2"
gem "rswag-api", "~> 2.17.0"
gem "rswag-ui", "~> 2.17.0"

gem "pghero", "~> 3.7"
gem "pg_query", ">= 2"

gem "connection_pool", "~> 3.0"
