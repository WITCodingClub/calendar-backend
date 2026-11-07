# frozen_string_literal: true

# Turns on the degree_planning flag (#944) for an example tagged
# :degree_planning. The flag is a row, so a before hook writes it inside the
# example's transaction. The after hook clears the Flipper cache, which no
# transaction rolls back.
RSpec.configure do |config|
  config.before(:each, :degree_planning) { Flipper.enable(FeatureFlags::DEGREE_PLANNING) }
  config.after(:each, :degree_planning)  { Flipper.disable(FeatureFlags::DEGREE_PLANNING) }
end
