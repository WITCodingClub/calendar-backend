# frozen_string_literal: true

# GoogleApiRateLimiter provides rate limiting and retry logic for Google Calendar API calls
#
# Features:
# - Exponential backoff for 429 rate limit errors
# - Configurable retry attempts and delays
# - Automatic throttling between batch operations
# - Respects Google's rate limit headers (if available)
#
# Usage:
#   include GoogleApiRateLimiter
#
#   with_rate_limit_handling do
#     service.insert_event(calendar_id, event)
#   end
#
module GoogleApiRateLimiter
  extend ActiveSupport::Concern

  # Configuration for rate limiting
  class RateLimitConfig
    attr_accessor :max_retries, :initial_delay, :max_delay, :backoff_multiplier, :batch_throttle_delay

    def initialize
      @max_retries = 5
      @initial_delay = 1.0 # seconds
      @max_delay = 32.0 # seconds
      @backoff_multiplier = 2.0
      @batch_throttle_delay = 0.1 # seconds between batch operations
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

  # Wrap a Google API call with rate limit handling
  #
  # @param max_retries [Integer] Maximum number of retry attempts (overrides config)
  # @yield The block containing the Google API call
  # @return The result of the block
  # @raise [Google::Apis::RateLimitError] if max retries exceeded
  def with_rate_limit_handling(max_retries: nil, &block)
    retries = 0
    max_attempts = max_retries || rate_limit_config.max_retries

    begin
      block.call
    rescue Google::Apis::RateLimitError, Google::Apis::ClientError => e
      # Handle 429 rate limit errors with exponential backoff
      if rate_limit_error?(e) && retries < max_attempts
        retries += 1
        delay = calculate_backoff_delay(retries, e)

        Rails.logger.warn "Google API rate limit hit (attempt #{retries}/#{max_attempts}). " \
                          "Retrying in #{delay} seconds. Error: #{e.message}"

        sleep(delay)
        retry
      else
        # Re-raise if not a rate limit error or max retries exceeded
        if retries >= max_attempts
          Rails.logger.error "Google API rate limit exceeded after #{max_attempts} retries. Giving up."
        end
        raise
      end
    end
  end

  # Execute batch operations with throttling between calls
  #
  # @param items [Array] Items to process
  # @param delay [Float] Delay in seconds between operations (overrides config)
  # @yield [item] Block to execute for each item
  # @return [Array] Results from each operation
  def with_batch_throttling(items, delay: nil, &block)
    throttle_delay = delay || rate_limit_config.batch_throttle_delay
    results = []

    return results if items.blank?

    items.each_with_index do |item, index|
      result = with_rate_limit_handling do
        block.call(item)
      end
      results << result

      # Sleep between operations (except after the last one)
      sleep(throttle_delay) if index < items.length - 1 && throttle_delay > 0
    end

    results
  end

  private

  # Check if error is a rate limit error
  def rate_limit_error?(error)
    return true if error.is_a?(Google::Apis::RateLimitError)

    # Some rate limit errors come through as ClientError with status 429
    if error.is_a?(Google::Apis::ClientError)
      return true if error.status_code == 429
      return true if error.message.match?(/rate limit/i)
      return true if error.message.match?(/quota.*exceeded/i)
      return true if error.message.match?(/user rate limit exceeded/i)
    end

    false
  end

  # Calculate exponential backoff delay
  #
  # Implements exponential backoff with jitter to prevent thundering herd
  #
  # @param attempt [Integer] Current retry attempt number
  # @param error [Google::Apis::Error] The error that triggered the retry
  # @return [Float] Delay in seconds
  def calculate_backoff_delay(attempt, error = nil)
    # Try to extract retry-after header from error if available
    if error.respond_to?(:header) && error.header&.[]("retry-after")
      retry_after = error.header["retry-after"].to_i
      return [retry_after, rate_limit_config.max_delay].min if retry_after.positive?
    end

    # Calculate exponential backoff: initial_delay * (multiplier ^ (attempt - 1))
    base_delay = rate_limit_config.initial_delay * (rate_limit_config.backoff_multiplier**(attempt - 1))

    # Cap at max_delay
    capped_delay = [base_delay, rate_limit_config.max_delay].min

    # Add jitter (±25% randomness) to prevent thundering herd
    jitter_factor = 0.75 + (rand * 0.5) # Random value between 0.75 and 1.25
    capped_delay * jitter_factor


  end
end
