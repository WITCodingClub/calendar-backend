# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingTimesIngestService do
  let(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    Course.create!(
      crn: 12345,
      term: term,
      title: "Data Structures",
      subject: "COMP",
      course_number: 2000,
      section_number: "01",
      schedule_type: "LEC",
      start_date: Date.new(2026, 9, 8),
      end_date: Date.new(2026, 12, 15)
    )
  end

  let(:raw_meeting_times) do
    [
      {
        "startDate"           => "09/08/2026",
        "endDate"             => "12/15/2026",
        "beginTime"           => "1300",
        "endTime"             => "1445",
        "building"            => "IRAH",
        "buildingDescription" => "Ira Allen Hall",
        "room"                => "112",
        "monday"              => true,
        "wednesday"           => true
      }
    ]
  end

  it "creates one meeting time per active day and returns their ids" do
    touched_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    expect(course.meeting_times.count).to eq(2)
    expect(touched_ids).to match_array(course.meeting_times.pluck(:id))
  end

  it "reuses existing meeting times on re-ingest instead of creating new rows" do
    first_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)
    second_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    expect(second_ids).to match_array(first_ids)
    expect(course.meeting_times.count).to eq(2)
  end

  it "does not include stale meeting times in the returned ids" do
    stale = Course::MeetingTime.create!(
      course: course,
      start_date: Time.zone.local(2026, 9, 8),
      end_date: Time.zone.local(2026, 12, 15, 23, 59, 59),
      begin_time: 900,
      end_time: 1045,
      day_of_week: :friday,
      meeting_schedule_type: :lecture,
      meeting_type: :class_meeting
    )

    touched_ids = described_class.call(course: course, raw_meeting_times: raw_meeting_times)

    expect(touched_ids).not_to include(stale.id)
  end
end
