# frozen_string_literal: true

require "rails_helper"

RSpec.describe Course::MeetingTimeRoom, type: :model do
  it { is_expected.to belong_to(:meeting_time).class_name("Course::MeetingTime") }
  it { is_expected.to belong_to(:room) }
end
