# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateLimitHeaders do
  let(:throttles) do
    {
      "req/ip"     => { limit: 600, period: 300, count: 1, epoch_time: 1_000_020, discriminator: "1.2.3.4" },
      "catalog/ip" => { limit: 300, period: 60,  count: 301, epoch_time: 1_000_020, discriminator: "1.2.3.4" }
    }
  end

  def call(path, throttle_data)
    app = lambda do |env|
      env["rack.attack.throttle_data"] = throttle_data
      [ 200, {}, [ "ok" ] ]
    end

    described_class.new(app).call(Rack::MockRequest.env_for(path))
  end

  it "describes each throttle as a quota policy" do
    _status, headers, _body = call("/api/v1/catalog/terms", throttles)

    expect(headers["ratelimit-policy"]).to eq('"req/ip";q=600;w=300, "catalog/ip";q=300;w=60')
  end

  it "sends the quota left and the seconds until each window resets, never below zero" do
    _status, headers, _body = call("/api/v1/catalog/terms", throttles)

    # 1_000_020 is 120 seconds into a 300-second window and 0 into a 60-second one.
    expect(headers["ratelimit"]).to eq('"req/ip";r=599;t=180, "catalog/ip";r=0;t=60')
  end

  it "adds nothing outside the API" do
    _status, headers, _body = call("/dashboard", throttles)

    expect(headers).not_to include("ratelimit", "ratelimit-policy")
  end

  it "adds nothing when no throttle counted the request" do
    _status, headers, _body = call("/api/v1/catalog/terms", nil)

    expect(headers).not_to include("ratelimit", "ratelimit-policy")
  end

  it "escapes a quote and a backslash in a policy name" do
    expect(described_class.sf_string(%(a"b\\c))).to eq(%("a\\"b\\\\c"))
  end

  it "runs outside Rack::Attack, so a 429 from Rack::Attack also gets the fields" do
    stack = Rails.application.middleware.middlewares.map(&:klass)

    expect(stack.index(described_class)).to be < stack.index(Rack::Attack)
  end
end
