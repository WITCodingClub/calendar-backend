# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingTimePolicy, type: :policy do
  it_behaves_like "public-read resource policy", :meeting_time
end
