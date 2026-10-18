# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::MeetingTimeSerializer do
  it "reports a lab meeting as a lab" do
    meeting = build(:course_meeting_time, meeting_schedule_type: :laboratory)

    expect(described_class.new(meeting).as_json[:meeting_type]).to eq("laboratory")
  end

  it "reports a lecture meeting as a lecture" do
    meeting = build(:course_meeting_time, meeting_schedule_type: :lecture)

    expect(described_class.new(meeting).as_json[:meeting_type]).to eq("lecture")
  end
end
