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

  before { allow(limiter).to receive(:sleep) }

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

    it "uses the job retries after a request block has ended" do
      # ExecutionContext.set puts the missing :controller key back as nil.
      ActiveSupport::ExecutionContext.set(controller: Object.new) { nil }
      attempts = 0

      expect { limiter.call_rate_limited { attempts += 1; raise rate_limit_error } }
        .to raise_error(Google::Apis::RateLimitError)

      expect(attempts).to be > described_class::REQUEST_MAX_RETRIES + 1
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
  # The google-apis gem picks the error class from the reason in a 403 body.
  # These examples send the real client through a stubbed response.
  describe "with a 403 from the Calendar API" do
    let(:service) { Google::Apis::CalendarV3::CalendarService.new }
    let(:url) { "https://www.googleapis.com/calendar/v3/calendars/cal-1/events/evt-1" }

    def forbidden(fixture)
      { status: 403, body: file_fixture("google_calendar/#{fixture}.json").read,
        headers: { "Content-Type" => "application/json" } }
    end

    def event_found
      { status: 200, body: file_fixture("google_calendar/event_created.json").read,
        headers: { "Content-Type" => "application/json" } }
    end

    %w[rate_limit_exceeded user_rate_limit_exceeded].each do |fixture|
      it "retries #{fixture.camelize(:lower)}" do
        stub = stub_request(:get, url).to_return(forbidden(fixture)).then.to_return(event_found)

        event = limiter.call_rate_limited { service.get_event("cal-1", "evt-1") }

        expect(event.id).to be_present
        expect(stub).to have_been_requested.twice
      end
    end

    it "raises RateLimitError, so a job can retry it later, when the limit lasts" do
      stub = stub_request(:get, url).to_return(forbidden("rate_limit_exceeded"))

      expect { limiter.call_rate_limited { service.get_event("cal-1", "evt-1") } }
        .to raise_error(Google::Apis::RateLimitError, /rateLimitExceeded/)
      expect(stub).to have_been_requested.times(described_class.config.max_retries + 1)
    end

    it "does not retry quotaExceeded, the Calendar usage limit" do
      stub = stub_request(:get, url).to_return(forbidden("quota_exceeded"))

      expect { limiter.call_rate_limited { service.get_event("cal-1", "evt-1") } }
        .to raise_error(Google::Apis::ClientError, /quotaExceeded/)
      expect(stub).to have_been_requested.once
    end
  end
end
