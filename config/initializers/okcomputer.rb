# frozen_string_literal: true

OkComputer::Registry.register "database", OkComputer::ActiveRecordCheck.new
OkComputer::Registry.register "cache", OkComputer::CacheCheck.new

OkComputer::Registry.register "app_version", OkComputer::AppVersionCheck.new
OkComputer::Registry.register "action_mailer", OkComputer::ActionMailerCheck.new

OkComputer.check_in_parallel = true
