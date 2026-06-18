# frozen_string_literal: true

module GoogleApiRateLimiter
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

  included do
    class_attribute :rate_limit_config, default: RateLimitConfig.new
  end

  class_methods do
    def configure_rate_limiting
      yield(rate_limit_config)
    end
  end

  def with_rate_limit_handling(max_retries: nil, &block)
    retries = 0
    max_attempts = max_retries || rate_limit_config.max_retries

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

  def rate_limit_error?(error)
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
      return [ retry_after, rate_limit_config.max_delay ].min if retry_after.positive?
    end

    base_delay    = rate_limit_config.initial_delay * (rate_limit_config.backoff_multiplier**(attempt - 1))
    capped_delay  = [ base_delay, rate_limit_config.max_delay ].min
    jitter_factor = 0.75 + (rand * 0.5)
    capped_delay * jitter_factor
  end
end
