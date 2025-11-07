# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MeetingTimePolicy, type: :policy do
  include_examples "public-read resource policy", :meeting_time
end
