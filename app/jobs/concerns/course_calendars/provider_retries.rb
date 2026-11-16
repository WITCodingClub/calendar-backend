# frozen_string_literal: true

module CourseCalendars
  # The retry rules of the jobs that call a calendar provider.
  #
  # A job waits only a few seconds inside a provider call (GoogleCalendar::RateLimiter,
  # the Faraday retry of MicrosoftGraph::Client), because a sleep holds a
  # worker thread. A longer limit leaves the job, and the job retries later.
  # The waits are about 3 s, 18 s, 83 s and 258 s. See
  # docs/google-calendar-rate-limits.md.
  module ProviderRetries
    extend ActiveSupport::Concern

    RETRY = { wait: :polynomially_longer, attempts: 5 }.freeze

    # A sync raises CourseCalendars::RateLimitError for any provider. A job
    # that calls a provider directly can get the provider's own error.
    RATE_LIMIT_ERRORS = [ CourseCalendars::RateLimitError, *CourseCalendars::Providers.rate_limit_errors ].freeze

    # Failures that can pass: a rate limit, a server error, or a Graph failure.
    TRANSIENT_ERRORS = [ *RATE_LIMIT_ERRORS, *CourseCalendars::Providers.transient_errors ].uniq.freeze

    # The provider refused the person's token. A retry cannot help until the
    # person connects the account again.
    AUTH_ERRORS = CourseCalendars::Providers.auth_errors.freeze

    class_methods do
      def retry_on_rate_limits
        retry_on(*RATE_LIMIT_ERRORS, **RETRY)
      end

      def retry_on_provider_errors(*more, attempts: RETRY[:attempts])
        retry_on(*TRANSIENT_ERRORS, *more, wait: RETRY[:wait], attempts: attempts)
      end

      # Declare it after retry_on_provider_errors: the handler declared last
      # wins, and MicrosoftGraph::AuthError is a MicrosoftGraph::Error.
      def discard_on_auth_errors
        discard_on(*AUTH_ERRORS)
      end
    end
  end
end
