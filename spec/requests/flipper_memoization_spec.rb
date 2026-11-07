# frozen_string_literal: true

require "rails_helper"

# Rails.cache is Solid Cache in production, so every Flipper read that misses
# the memoizer is a database query. The privileged-users safelist in
# Rack::Attack reads a flag on each API request with a token, so the memoizer
# must run before Rack::Attack (#682).
RSpec.describe "Flipper memoization" do
  it "puts one Flipper memoizer before Rack::Attack" do
    stack = Rails.application.middleware.map(&:klass)

    expect(stack.count(Flipper::Middleware::Memoizer)).to eq(1)
    expect(stack.index(Flipper::Middleware::Memoizer)).to be < stack.index(Rack::Attack)
  end

  it "reads the bypass flag in the safelist from the memoized flags" do
    user = create(:user)
    token = JsonWebTokenService.issue(user: user, source: "passkey")
    memoizing = []
    allow(Flipper).to receive(:enabled?).and_wrap_original do |original, *args|
      memoizing << Flipper.memoizing? if args.first == FeatureFlags::BYPASS_RATE_LIMITS
      original.call(*args)
    end

    get "/api/user/feature_flags", headers: { "Authorization" => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    expect(memoizing).to include(true)
    expect(memoizing).not_to include(false)
  end

  it "keeps flag reads out of Rails.cache outside the test environment" do
    initializer = Rails.root.join("config/initializers/flipper.rb").read

    expect(initializer).to include("ActiveSupportCacheStore, FLIPPER_CACHE, FLIPPER_CACHE_TTL")
    expect(initializer).to match(/FLIPPER_CACHE = Rails\.env\.test\? \? Rails\.cache : ActiveSupport::Cache::MemoryStore\.new/)
  end
end
