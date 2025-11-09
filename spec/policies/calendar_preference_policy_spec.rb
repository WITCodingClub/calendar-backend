# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarPreferencePolicy, type: :policy do
  it_behaves_like "user-owned resource policy", :calendar_preference
end
