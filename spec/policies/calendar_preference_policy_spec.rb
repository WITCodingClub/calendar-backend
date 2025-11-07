# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CalendarPreferencePolicy, type: :policy do
  include_examples "user-owned resource policy", :calendar_preference
end
