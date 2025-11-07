# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventPreferencePolicy, type: :policy do
  include_examples "user-owned resource policy", :event_preference
end
