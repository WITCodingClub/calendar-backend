# frozen_string_literal: true

# https://github.com/jphenow/okcomputer#registering-additional-checks
#
# class MyCustomCheck < OKComputer::Check
#   def call
#     if rand(10).even?
#       "Even is great!"
#     else
#       mark_failure
#       "We don't like odd numbers"
#     end
#   end
# end

OkComputer::Registry.register "database", OkComputer::ActiveRecordCheck.new
OkComputer::Registry.register "cache", OkComputer::CacheCheck.new

OkComputer::Registry.register "app_version", OkComputer::AppVersionCheck.new
OkComputer::Registry.register "action_mailer", OkComputer::ActionMailerCheck.new

# Run checks in parallel
OkComputer.check_in_parallel = true

# Log when health checks are run
OkComputer.logger = Rails.logger
