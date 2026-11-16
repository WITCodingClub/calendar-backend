# frozen_string_literal: true

module CourseCalendars
  # A provider kept refusing calls for its rate limit. CourseCalendars::Provider
  # raises it in place of the provider's own error class, and the sync jobs
  # retry it later (CourseCalendars::ProviderRetries). The cause is the
  # provider's error.
  class RateLimitError < StandardError; end
end
