# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleApiRateLimiter do
  # Create a dummy class to test the concern
  let(:dummy_class) do
    Class.new do
      include GoogleApiRateLimiter

      def service_call
        # Simulates a Google API call
        yield if block_given?
      end
    end
  end

  let(:instance) { dummy_class.new }

  describe "#with_rate_limit_handling" do
    context "when API call succeeds" do
      it "returns the result of the block" do
        result = instance.with_rate_limit_handling do
          "success"
        end

        expect(result).to eq("success")
      end

      it "executes the block without retries" do
        call_count = 0
        instance.with_rate_limit_handling do
          call_count += 1
          "success"
        end

        expect(call_count).to eq(1)
      end
    end

    context "when API returns rate limit error" do
      it "retries on Google::Apis::RateLimitError" do
        call_count = 0
        allow(instance).to receive(:sleep) # Don't actually sleep in tests

        result = instance.with_rate_limit_handling do
          call_count += 1
          raise Google::Apis::RateLimitError.new("Rate limit exceeded") if call_count < 3

          "success"
        end

        expect(call_count).to eq(3)
        expect(result).to eq("success")
      end

      it "retries on ClientError with status 429" do
        call_count = 0
        allow(instance).to receive(:sleep)

        result = instance.with_rate_limit_handling do
          call_count += 1
          if call_count < 3
            error = Google::Apis::ClientError.new("Rate limit exceeded")
            allow(error).to receive(:status_code).and_return(429)
            raise error
          end
          "success"
        end

        expect(call_count).to eq(3)
        expect(result).to eq("success")
      end

      it "uses exponential backoff" do
        call_count = 0
        sleep_delays = []

        allow(instance).to receive(:sleep) do |delay|
          sleep_delays << delay
        end

        instance.with_rate_limit_handling do
          call_count += 1
          raise Google::Apis::RateLimitError.new("Rate limit exceeded") if call_count < 4

          "success"
        end

        # Check that delays are increasing (exponential backoff)
        expect(sleep_delays.length).to eq(3)
        expect(sleep_delays[1]).to be > sleep_delays[0]
        expect(sleep_delays[2]).to be > sleep_delays[1]
      end

      it "respects retry-after header when present" do
        call_count = 0
        sleep_delay = nil

        allow(instance).to receive(:sleep) do |delay|
          sleep_delay = delay
        end

        instance.with_rate_limit_handling do
          call_count += 1
          if call_count == 1
            error = Google::Apis::RateLimitError.new("Rate limit exceeded")
            allow(error).to receive(:header).and_return({ "retry-after" => "10" })
            raise error
          end
          "success"
        end

        expect(sleep_delay).to eq(10)
      end

      it "caps delay at max_delay" do
        call_count = 0
        sleep_delays = []

        # Set a low max_delay for testing
        instance.rate_limit_config.max_delay = 5.0

        allow(instance).to receive(:sleep) do |delay|
          sleep_delays << delay
        end

        instance.with_rate_limit_handling do
          call_count += 1
          raise Google::Apis::RateLimitError.new("Rate limit exceeded") if call_count < 6

          "success"
        end

        # All delays should be capped at max_delay with jitter (5.0 * 1.25 = 6.25)
        # Jitter adds up to 25% randomness, so max possible is 1.25x the capped value
        sleep_delays.each do |delay|
          expect(delay).to be <= 6.25
        end
      end

      it "gives up after max_retries" do
        allow(instance).to receive(:sleep)

        expect do
          instance.with_rate_limit_handling(max_retries: 3) do
            raise Google::Apis::RateLimitError.new("Rate limit exceeded")
          end
        end.to raise_error(Google::Apis::RateLimitError)
      end

      it "logs warnings on retry" do
        call_count = 0
        allow(instance).to receive(:sleep)
        allow(Rails.logger).to receive(:warn)

        instance.with_rate_limit_handling do
          call_count += 1
          raise Google::Apis::RateLimitError.new("Rate limit exceeded") if call_count < 2

          "success"
        end

        expect(Rails.logger).to have_received(:warn).once
      end

      it "logs error when max retries exceeded" do
        allow(instance).to receive(:sleep)
        allow(Rails.logger).to receive(:error)

        begin
          instance.with_rate_limit_handling(max_retries: 2) do
            raise Google::Apis::RateLimitError.new("Rate limit exceeded")
          end
        rescue Google::Apis::RateLimitError
          # Expected
        end

        expect(Rails.logger).to have_received(:error).once
      end
    end

    context "when API returns other errors" do
      it "does not retry on non-rate-limit errors" do
        call_count = 0

        expect do
          instance.with_rate_limit_handling do
            call_count += 1
            raise Google::Apis::ServerError.new("Server error")
          end
        end.to raise_error(Google::Apis::ServerError)

        expect(call_count).to eq(1)
      end

      it "does not retry on ClientError with status other than 429" do
        call_count = 0

        expect do
          instance.with_rate_limit_handling do
            call_count += 1
            error = Google::Apis::ClientError.new("Bad request")
            allow(error).to receive(:status_code).and_return(400)
            raise error
          end
        end.to raise_error(Google::Apis::ClientError)

        expect(call_count).to eq(1)
      end
    end
  end

  describe "#with_batch_throttling" do
    it "processes all items" do
      items = [1, 2, 3, 4, 5]
      results = []

      instance.with_batch_throttling(items, delay: 0) do |item|
        results << item * 2
      end

      expect(results).to eq([2, 4, 6, 8, 10])
    end

    it "throttles between items" do
      items = [1, 2, 3]
      sleep_count = 0

      allow(instance).to receive(:sleep) do
        sleep_count += 1
      end

      instance.with_batch_throttling(items, delay: 0.1) do |item|
        item * 2
      end

      # Should sleep between items (not after the last one)
      expect(sleep_count).to eq(items.length - 1)
    end

    it "uses configured batch_throttle_delay by default" do
      items = [1, 2]
      sleep_delay = nil

      instance.rate_limit_config.batch_throttle_delay = 0.5

      allow(instance).to receive(:sleep) do |delay|
        sleep_delay = delay
      end

      instance.with_batch_throttling(items) do |item|
        item * 2
      end

      expect(sleep_delay).to eq(0.5)
    end

    it "wraps each item with rate limit handling" do
      items = [1, 2, 3]
      call_counts = Hash.new(0)

      allow(instance).to receive(:sleep)

      instance.with_batch_throttling(items, delay: 0) do |item|
        call_counts[item] += 1
        if call_counts[item] < 2
          raise Google::Apis::RateLimitError.new("Rate limit exceeded")
        end
        item * 2
      end

      # Each item should have been called twice (once failed, once succeeded)
      expect(call_counts.values).to all(eq(2))
    end

    it "returns results for all items" do
      items = [1, 2, 3]

      results = instance.with_batch_throttling(items, delay: 0) do |item|
        item * 2
      end

      expect(results).to eq([2, 4, 6])
    end

    it "does not sleep after last item" do
      items = [1, 2]
      sleep_calls = []

      allow(instance).to receive(:sleep) do |delay|
        sleep_calls << delay
      end

      instance.with_batch_throttling(items, delay: 0.1) do |item|
        item
      end

      # Should only sleep once (after first item, not after second)
      expect(sleep_calls.length).to eq(1)
    end

    it "handles empty array" do
      results = instance.with_batch_throttling([], delay: 0) do |item|
        item
      end

      expect(results).to eq([])
    end

    it "skips sleep when delay is 0" do
      items = [1, 2, 3]

      allow(instance).to receive(:sleep)

      instance.with_batch_throttling(items, delay: 0) do |item|
        item
      end

      expect(instance).not_to have_received(:sleep)
    end
  end

  describe ".configure_rate_limiting" do
    it "allows configuration of max_retries" do
      dummy_class.configure_rate_limiting do |config|
        config.max_retries = 10
      end

      expect(dummy_class.rate_limit_config.max_retries).to eq(10)
    end

    it "allows configuration of initial_delay" do
      dummy_class.configure_rate_limiting do |config|
        config.initial_delay = 2.5
      end

      expect(dummy_class.rate_limit_config.initial_delay).to eq(2.5)
    end

    it "allows configuration of max_delay" do
      dummy_class.configure_rate_limiting do |config|
        config.max_delay = 60.0
      end

      expect(dummy_class.rate_limit_config.max_delay).to eq(60.0)
    end

    it "allows configuration of backoff_multiplier" do
      dummy_class.configure_rate_limiting do |config|
        config.backoff_multiplier = 3.0
      end

      expect(dummy_class.rate_limit_config.backoff_multiplier).to eq(3.0)
    end

    it "allows configuration of batch_throttle_delay" do
      dummy_class.configure_rate_limiting do |config|
        config.batch_throttle_delay = 0.5
      end

      expect(dummy_class.rate_limit_config.batch_throttle_delay).to eq(0.5)
    end
  end

  describe "rate_limit_error?" do
    it "returns true for RateLimitError" do
      error = Google::Apis::RateLimitError.new("Rate limit exceeded")
      expect(instance.send(:rate_limit_error?, error)).to be true
    end

    it "returns true for ClientError with status 429" do
      error = Google::Apis::ClientError.new("Rate limit exceeded")
      allow(error).to receive(:status_code).and_return(429)
      expect(instance.send(:rate_limit_error?, error)).to be true
    end

    it "returns true for ClientError with rate limit in message" do
      error = Google::Apis::ClientError.new("User rate limit exceeded")
      allow(error).to receive(:status_code).and_return(403)
      expect(instance.send(:rate_limit_error?, error)).to be true
    end

    it "returns true for ClientError with quota exceeded in message" do
      error = Google::Apis::ClientError.new("Quota has been exceeded")
      allow(error).to receive(:status_code).and_return(403)
      expect(instance.send(:rate_limit_error?, error)).to be true
    end

    it "returns false for other ClientErrors" do
      error = Google::Apis::ClientError.new("Bad request")
      allow(error).to receive(:status_code).and_return(400)
      expect(instance.send(:rate_limit_error?, error)).to be false
    end

    it "returns false for other errors" do
      error = StandardError.new("Some error")
      expect(instance.send(:rate_limit_error?, error)).to be false
    end
  end

  describe "calculate_backoff_delay" do
    it "calculates exponential backoff correctly" do
      instance.rate_limit_config.initial_delay = 1.0
      instance.rate_limit_config.backoff_multiplier = 2.0
      instance.rate_limit_config.max_delay = 100.0

      # First retry: ~1.0 seconds (with jitter)
      delay1 = instance.send(:calculate_backoff_delay, 1)
      expect(delay1).to be_between(0.75, 1.25)

      # Second retry: ~2.0 seconds (with jitter)
      delay2 = instance.send(:calculate_backoff_delay, 2)
      expect(delay2).to be_between(1.5, 2.5)

      # Third retry: ~4.0 seconds (with jitter)
      delay3 = instance.send(:calculate_backoff_delay, 3)
      expect(delay3).to be_between(3.0, 5.0)
    end

    it "adds jitter to prevent thundering herd" do
      instance.rate_limit_config.initial_delay = 1.0
      instance.rate_limit_config.backoff_multiplier = 2.0
      instance.rate_limit_config.max_delay = 100.0

      # Call multiple times and check that we get different values (due to jitter)
      delays = 10.times.map { instance.send(:calculate_backoff_delay, 1) }

      # Not all delays should be exactly the same (jitter adds randomness)
      expect(delays.uniq.length).to be > 1
    end
  end
end
