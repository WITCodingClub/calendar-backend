# frozen_string_literal: true

# Catalog::BannerThrottle keeps its token bucket and cooldown in memory for
# the whole process. Each example starts with a full bucket and no cooldown,
# and never sleeps: a retry or a pacing wait returns at once.
RSpec.configure do |config|
  config.before do
    Catalog::BannerThrottle.reset!
    allow(Catalog::BannerThrottle).to receive(:pause)
  end
end
