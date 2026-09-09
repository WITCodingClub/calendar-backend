# frozen_string_literal: true

require "rails_helper"

RSpec.describe CalendarTemplateRenderer do
  let(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    Course.create!(
      crn: 16004, term: term, title: "Calculus 2A", subject: "MATH",
      course_number: 1876, section_number: "03", schedule_type: "LEC",
      start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 10, 20)
    )
  end

  let(:meeting_time) do
    MeetingTimesIngestService.call(
      course: course,
      raw_meeting_times: [
        {
          "startDate"           => "09/08/2026",
          "endDate"             => "10/20/2026",
          "beginTime"           => "1300",
          "endTime"             => "1410",
          "building"            => "BEATT",
          "buildingDescription" => "Beatty Hall",
          "room"                => "420",
          "monday"              => true
        }
      ]
    )
    course.meeting_times.first
  end

  let!(:minevich) do
    Faculty.create!(email: "minevichi@wit.edu", first_name: "Igor", last_name: "Minevich")
  end

  let!(:sanderson) do
    Faculty.create!(email: "sandersone1@wit.edu", first_name: "Elijah", last_name: "Sanderson")
  end

  # The instructor who was attached first is not always the one teaching the
  # section. Before the join carried Banner's primary flag, the event named
  # whichever row was oldest.
  it "names Banner's primary instructor, not the oldest join row" do
    CourseFaculty.create!(course: course, faculty: minevich, primary_indicator: false)
    CourseFaculty.create!(course: course, faculty: sanderson, primary_indicator: true)

    context = described_class.build_context_from_meeting_time(meeting_time)

    expect(context[:faculty]).to eq("Elijah Sanderson")
    expect(context[:faculty_email]).to eq("sandersone1@wit.edu")
  end

  it "lists every instructor with the primary one first" do
    CourseFaculty.create!(course: course, faculty: minevich, primary_indicator: false)
    CourseFaculty.create!(course: course, faculty: sanderson, primary_indicator: true)

    context = described_class.build_context_from_meeting_time(meeting_time)

    expect(context[:all_faculty]).to eq("Elijah Sanderson, Igor Minevich")
  end

  it "leaves the instructor blank when the section has none" do
    context = described_class.build_context_from_meeting_time(meeting_time)

    expect(context[:faculty]).to eq("")
    expect(context[:faculty_email]).to eq("")
  end
end
