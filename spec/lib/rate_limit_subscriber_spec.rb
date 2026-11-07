# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateLimitSubscriber do
  def limited_count(throttle)
    Yabeda.calendar.rate_limited_total.get(throttle: throttle) || 0
  end

  def throttled_request(throttle, count:, limit: 5, period: 60)
    env = Rack::MockRequest.env_for("/api/user/onboard", "REMOTE_ADDR" => "203.0.113.40")
    env["rack.attack.matched"] = throttle
    env["rack.attack.match_data"] = { discriminator: "203.0.113.40", count: count, limit: limit, period: period }
    Rack::Attack::Request.new(env)
  end

  it "counts each refused request by throttle name" do
    expect { described_class.call(throttled_request("spec/limit", count: 6)) }
      .to change { limited_count("spec/limit") }.by(1)
  end

  it "logs the first refusal in a window, without the key" do
    allow(Rails.logger).to receive(:warn)

    described_class.call(throttled_request("spec/limit", count: 6))
    described_class.call(throttled_request("spec/limit", count: 7))

    expect(Rails.logger).to have_received(:warn).once do |line|
      expect(JSON.parse(line)).to eq("message" => "rate_limited", "throttle" => "spec/limit", "limit" => 5, "period" => 60)
      expect(line).not_to include("203.0.113.40")
    end
  end

  it "does not raise when the counter fails, so the client still gets its 429" do
    allow(Yabeda.calendar.rate_limited_total).to receive(:increment).and_raise(RuntimeError, "no store")
    allow(Rails.logger).to receive(:warn)

    expect { described_class.call(throttled_request("spec/limit", count: 6)) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/RateLimitSubscriber failed: RuntimeError/)
  end

  it "is subscribed to the requests that Rack::Attack throttles" do
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    limit = Rack::Attack.throttles.fetch("meet/pick/ip").limit
    env = { method: "POST", "REMOTE_ADDR" => "203.0.113.41", "HTTP_USER_AGENT" => "Mozilla/5.0" }

    post_meeting_pick = lambda do
      status, _headers, body = Rails.application.call(Rack::MockRequest.env_for("/meet/sample-token", **env))
      # Rails.cache keeps a local cache until the body closes.
      body.close if body.respond_to?(:close)
      status
    end
    limit.times { post_meeting_pick.call }

    expect { expect(post_meeting_pick.call).to eq(429) }.to change { limited_count("meet/pick/ip") }.by(1)
  ensure
    Rack::Attack.cache.store = original_store
  end
end
