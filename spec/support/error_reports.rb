# frozen_string_literal: true

require "active_support/testing/error_reporter_assertions"

# capture_error_reports { ... } returns the errors that the block reported to
# Rails.error, with handled, severity, context, and source.
RSpec.configure do |config|
  config.include ActiveSupport::Testing::ErrorReporterAssertions
end
