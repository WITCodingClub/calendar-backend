# frozen_string_literal: true

module GoogleCalendar
  module RateLimiter
    extend ActiveSupport::Concern

    class RateLimitConfig
      attr_accessor :max_retries, :initial_delay, :max_delay, :backoff_multiplier, :batch_throttle_delay

      def initialize
        @max_retries          = 5
        @initial_delay        = 1.0
        @max_delay            = 32.0
        @backoff_multiplier   = 2.0
        @batch_throttle_delay = 0.1
      end
    end

    # Inside a web request, a long backoff holds one of the few Puma threads.
    # A request retries once, after a short wait, and leaves longer waits to
    # the jobs that retry on Google::Apis::RateLimitError.
    REQUEST_MAX_RETRIES = 1
    REQUEST_MAX_DELAY   = 2.0

    # Google answers with these reasons when a daily or per-user usage limit is
    # used up. The limit does not reset within seconds, so a retry only waits.
    # "rateLimitExceeded: Quota exceeded for quota metric ... per minute" is a
    # short limit, and does not match.
    NON_RETRYABLE_REASONS = /\b(?:dailyLimitExceeded|quotaExceeded)\b|daily limit|usage limits exceeded/i

    # One config for every class that includes the concern, so the GOOGLE_API_*
    # settings in config/initializers/google_api_rate_limiting.rb apply to all.
    def self.config
      @config ||= RateLimitConfig.new
    end

    def self.configure
      yield(config)
    end

    included do
      class_attribute :rate_limit_config, default: GoogleCalendar::RateLimiter.config
    end

    def with_rate_limit_handling(max_retries: nil, &block)
      # Calls nest, as when with_batch_throttling wraps a method that also
      # handles rate limits. The outer call does the retries, so the attempts
      # do not multiply.
      return block.call if @within_rate_limit_handling

      begin
        @within_rate_limit_handling = true
        retry_rate_limited(max_retries || max_rate_limit_retries, &block)
      ensure
        @within_rate_limit_handling = false
      end
    end

    def with_batch_throttling(items, delay: nil, &block)
      throttle_delay = delay || rate_limit_config.batch_throttle_delay
      results = []

      return results if items.blank?

      items.each_with_index do |item, index|
        result = with_rate_limit_handling { block.call(item) }
        results << result

        sleep(throttle_delay) if index < items.length - 1 && throttle_delay > 0
      end

      results
    end

    private

    def retry_rate_limited(max_attempts, &block)
      retries = 0

      begin
        block.call
      rescue Google::Apis::RateLimitError, Google::Apis::ClientError => e
        if rate_limit_error?(e) && retries < max_attempts
          retries += 1
          delay = calculate_backoff_delay(retries, e)

          Rails.logger.warn "Google API rate limit hit (attempt #{retries}/#{max_attempts}). " \
                            "Retrying in #{delay} seconds. Error: #{e.message}"

          sleep(delay)
          retry
        else
          Rails.logger.error "Google API rate limit exceeded after #{max_attempts} retries. Giving up." if retries >= max_attempts
          raise
        end
      end
    end

    # Rails sets ExecutionContext[:controller] for the length of a request.
    def in_web_request?
      ActiveSupport::ExecutionContext.to_h.key?(:controller)
    end

    def max_rate_limit_retries
      in_web_request? ? [ rate_limit_config.max_retries, REQUEST_MAX_RETRIES ].min : rate_limit_config.max_retries
    end

    def max_backoff_delay
      in_web_request? ? [ rate_limit_config.max_delay, REQUEST_MAX_DELAY ].min : rate_limit_config.max_delay
    end

    def rate_limit_error?(error)
      return false if error.message.to_s.match?(NON_RETRYABLE_REASONS)
      return true if error.is_a?(Google::Apis::RateLimitError)

      if error.is_a?(Google::Apis::ClientError)
        return true if error.status_code == 429
        return true if error.message.match?(/rate limit/i)
        return true if error.message.match?(/quota.*exceeded/i)
        return true if error.message.match?(/user rate limit exceeded/i)
      end

      false
    end

    def calculate_backoff_delay(attempt, error = nil)
      if error.respond_to?(:header) && error.header&.[]("retry-after")
        retry_after = error.header["retry-after"].to_i
        return [ retry_after, max_backoff_delay ].min if retry_after.positive?
      end

      base_delay    = rate_limit_config.initial_delay * (rate_limit_config.backoff_multiplier**(attempt - 1))
      capped_delay  = [ base_delay, max_backoff_delay ].min
      jitter_factor = 0.75 + (rand * 0.5)
      capped_delay * jitter_factor
    end
  end
end
