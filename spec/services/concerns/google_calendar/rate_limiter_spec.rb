# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::RateLimiter do
  let(:limiter_class) do
    Class.new do
      include GoogleCalendar::RateLimiter

      def call_rate_limited(&) = with_rate_limit_handling(&)
    end
  end

  let(:limiter) { limiter_class.new }

  def rate_limit_error(message = "rateLimitExceeded: Rate Limit Exceeded")
    Google::Apis::RateLimitError.new(message, status_code: 429)
  end

  before do
    allow(limiter).to receive(:sleep)
    # A request spec that ran earlier in this process can leave :controller set.
    ActiveSupport::ExecutionContext.clear
  end

  describe "config" do
    it "shares one config between every class that includes the concern" do
      expect(GoogleCalendar::Provider.rate_limit_config).to be(described_class.config)
      expect(GoogleCalendar::EventLabels.rate_limit_config).to be(described_class.config)
      expect(Cleanup::UntrackedGoogleEventsJob.rate_limit_config).to be(described_class.config)
    end
  end

  describe "#with_rate_limit_handling" do
    it "retries a rate limit error with backoff in a job" do
      attempts = 0

      result = limiter.call_rate_limited do
        attempts += 1
        raise rate_limit_error if attempts < 3

        :done
      end

      expect(result).to eq(:done)
      expect(limiter).to have_received(:sleep).twice
    end

    it "gives up after the configured number of retries" do
      attempts = 0

      expect { limiter.call_rate_limited { attempts += 1; raise rate_limit_error } }
        .to raise_error(Google::Apis::RateLimitError)
      expect(attempts).to eq(described_class.config.max_retries + 1)
    end

    it "retries once, after a short wait, inside a web request" do
      attempts = 0

      ActiveSupport::ExecutionContext.set(controller: Object.new) do
        expect { limiter.call_rate_limited { attempts += 1; raise rate_limit_error } }
          .to raise_error(Google::Apis::RateLimitError)
      end

      expect(attempts).to eq(described_class::REQUEST_MAX_RETRIES + 1)
      expect(limiter).to have_received(:sleep).with(a_value <= described_class::REQUEST_MAX_DELAY * 1.25)
    end

    it "caps a long Retry-After inside a web request" do
      error = rate_limit_error
      allow(error).to receive(:header).and_return("retry-after" => "30")
      attempts = 0

      ActiveSupport::ExecutionContext.set(controller: Object.new) do
        limiter.call_rate_limited do
          attempts += 1
          raise error if attempts == 1
        end
      end

      expect(limiter).to have_received(:sleep).with(described_class::REQUEST_MAX_DELAY)
    end

    it "does not multiply the attempts when calls nest" do
      attempts = 0

      expect do
        limiter.call_rate_limited do
          limiter.call_rate_limited { attempts += 1; raise rate_limit_error }
        end
      end.to raise_error(Google::Apis::RateLimitError)

      expect(attempts).to eq(described_class.config.max_retries + 1)
    end

    [
      "dailyLimitExceeded: Daily Limit Exceeded",
      "quotaExceeded: Calendar usage limits exceeded."
    ].each do |message|
      it "does not retry #{message.split(':').first}, which does not reset within seconds" do
        attempts = 0

        expect { limiter.call_rate_limited { attempts += 1; raise rate_limit_error(message) } }
          .to raise_error(Google::Apis::RateLimitError)
        expect(attempts).to eq(1)
      end
    end

    it "retries a per-minute quota error" do
      message = "rateLimitExceeded: Quota exceeded for quota metric 'Queries' and limit 'Queries per minute per user'"
      error   = Google::Apis::ClientError.new(message, status_code: 403)
      attempts = 0

      limiter.call_rate_limited do
        attempts += 1
        raise error if attempts == 1
      end

      expect(attempts).to eq(2)
    end
  end
end
