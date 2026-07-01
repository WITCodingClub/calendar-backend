# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingTimesIngestService do
  let(:term) do
    Term.create!(uid: 202601, season: :spring, year: 2026,
                 start_date: Date.new(2026, 1, 15), end_date: Date.new(2026, 5, 1))
  end

  let(:course) do
    Course.create!(term: term, crn: 12_345, course_number: 1000, section_number: "01",
                   subject: "COMP", title: "Intro to Computing", schedule_type: :lecture,
                   start_date: term.start_date, end_date: term.end_date)
  end

  let(:raw) do
    [ {
      "startDate" => "2026-01-15", "endDate" => "2026-05-01",
      "beginTime" => "0800", "endTime" => "0915",
      "monday" => true, "building" => "IRA", "room" => "101"
    } ]
  end

  it "returns the ids of the meeting times it created" do
    kept = described_class.call(course: course, raw_meeting_times: raw)

    expect(kept).to contain_exactly(course.meeting_times.sole.id)
  end

  it "upserts stable ids on re-ingest rather than recreating rows" do
    first_ids  = described_class.call(course: course, raw_meeting_times: raw)
    second_ids = described_class.call(course: course, raw_meeting_times: raw)

    expect(second_ids).to eq(first_ids)
    expect(course.meeting_times.count).to eq(1)
  end

  it "does not touch meeting times when reconciled against the kept ids" do
    described_class.call(course: course, raw_meeting_times: raw)
    original = course.meeting_times.sole

    kept = described_class.call(course: course, raw_meeting_times: raw)
    course.meeting_times.where.not(id: kept).destroy_all if kept.any?

    expect(course.meeting_times.reload).to contain_exactly(original)
  end
end
