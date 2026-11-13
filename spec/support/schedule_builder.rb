# frozen_string_literal: true

# Turns on the schedule_builder flag (#997) for an example tagged
# :schedule_builder, the same way spec/support/degree_planning.rb does.
RSpec.configure do |config|
  config.before(:each, :schedule_builder) { Flipper.enable(FeatureFlags::SCHEDULE_BUILDER) }
  config.after(:each, :schedule_builder)  { Flipper.disable(FeatureFlags::SCHEDULE_BUILDER) }
end
