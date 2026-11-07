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

  describe "the flag cache" do
    def cache_adapter
      adapter = Flipper.adapter
      adapter = adapter.adapter until adapter.is_a?(Flipper::Adapters::ActiveSupportCacheStore)
      adapter
    end

    it "puts the cache from FeatureFlags.build_cache in front of the flag store" do
      expect(cache_adapter.cache).to be(Rails.cache)
      expect(cache_adapter.ttl).to eq(FeatureFlags::CACHE_TTL)
    end

    it "keeps flag reads in the process outside the test environment" do
      cache = FeatureFlags.build_cache(env: ActiveSupport::EnvironmentInquirer.new("production"))

      expect(cache).to be_a(ActiveSupport::Cache::MemoryStore)
      expect(cache).not_to be(Rails.cache)
    end

    it "shows a flag change from the same process at once" do
      store = Flipper::Adapters::Memory.new
      cache = FeatureFlags.build_cache(env: ActiveSupport::EnvironmentInquirer.new("production"))
      flipper = Flipper.new(Flipper::Adapters::ActiveSupportCacheStore.new(store, cache, FeatureFlags::CACHE_TTL))
      flipper.add(:sample_flag)
      flipper.preload_all

      flipper.enable(:sample_flag)

      expect(flipper.enabled?(:sample_flag)).to be(true)
    end
  end
end
