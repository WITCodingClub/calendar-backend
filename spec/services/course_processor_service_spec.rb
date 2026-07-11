# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseProcessorService do
  let(:user) { User.create!(email: "student@wit.edu", password: "password123") }
  let!(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }

  let(:class_details) do
    {
      title: "Data Structures",
      subject: "COMP",
      section_number: "01",
      credit_hours: 4,
      grade_mode: "Standard Letter",
      seats_available: 10,
      seats_capacity: 30,
      schedule_type: "Lecture (LEC)",
      meeting_times: [
        {
          "building"             => "IRAH",
          "building_description" => "Ira Allen Hall",
          "room"                 => "112",
          "startDate"            => "09/08/2026",
          "endDate"              => "12/15/2026",
          "startTime"            => "1300",
          "endTime"              => "1445",
          "days"                 => { "monday" => true, "wednesday" => true }
        }
      ]
    }
  end

  let(:courses_payload) { [ { crn: "12345", term: "202710", courseNumber: "2000" } ] }

  before do
    allow(LeopardWebService).to receive(:get_class_details).and_return(class_details)
  end

  def process!
    described_class.new(courses_payload, user).call
  end

  it "creates the course, meeting times, and enrollment" do
    process!

    course = Course.find_by(crn: 12345, term: term)
    expect(course).to be_present
    expect(course.meeting_times.count).to eq(2)
    expect(user.enrollments.where(course: course)).to exist
  end

  it "keeps meeting time ids stable across re-processing" do
    process!
    original_ids = Course.find_by(crn: 12345).meeting_times.pluck(:id)

    process!

    expect(Course.find_by(crn: 12345).meeting_times.pluck(:id)).to match_array(original_ids)
  end

  it "preserves google_calendar_events tracking rows across re-processing" do
    process!
    course = Course.find_by(crn: 12345)
    meeting_time = course.meeting_times.first

    credential = user.oauth_credentials.create!(
      provider: "google", uid: "google-uid", email: user.email, access_token: "token"
    )
    calendar = credential.create_google_calendar!(google_calendar_id: "cal_123")
    event = calendar.google_calendar_events.create!(
      google_event_id: "evt_123", meeting_time: meeting_time
    )

    process!

    expect(event.reload.meeting_time_id).to eq(meeting_time.id)
  end

  it "removes meeting times that are no longer in the upload, nullifying their events" do
    process!
    course = Course.find_by(crn: 12345)

    credential = user.oauth_credentials.create!(
      provider: "google", uid: "google-uid", email: user.email, access_token: "token"
    )
    calendar = credential.create_google_calendar!(google_calendar_id: "cal_123")
    stale_meeting_time = course.meeting_times.find_by(day_of_week: :wednesday)
    event = calendar.google_calendar_events.create!(
      google_event_id: "evt_stale", meeting_time: stale_meeting_time
    )

    class_details[:meeting_times].first["days"] = { "monday" => true }
    process!

    expect(course.meeting_times.pluck(:day_of_week)).to eq([ "monday" ])
    expect(event.reload.meeting_time_id).to be_nil
    expect(GoogleCalendarEvent.orphaned).to include(event)
  end
end
