# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventPreferencePolicy, type: :policy do
  it_behaves_like "user-owned resource policy", :event_preference
end
