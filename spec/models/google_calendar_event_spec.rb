# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarEvent, type: :model do
  let(:user) { User.create!(email: "student@wit.edu", password: "password123") }
  let(:credential) do
    user.oauth_credentials.create!(
      provider: "google", uid: "google-uid", email: user.email, access_token: "token"
    )
  end
  let(:calendar) { credential.create_google_calendar!(google_calendar_id: "cal_123") }

  let(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    Course.create!(
      crn: 12345, term: term, title: "Data Structures", subject: "COMP",
      course_number: 2000, section_number: "01", schedule_type: "LEC",
      start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)
    )
  end

  describe "orphaning behavior" do
    it "is nullified, not destroyed, when its meeting time is destroyed" do
      meeting_time = Course::MeetingTime.create!(
        course: course,
        start_date: Time.zone.local(2026, 9, 8),
        end_date: Time.zone.local(2026, 12, 15, 23, 59, 59),
        begin_time: 1300, end_time: 1445,
        day_of_week: :monday,
        meeting_schedule_type: :lecture, meeting_type: :class_meeting
      )
      event = calendar.google_calendar_events.create!(
        google_event_id: "evt_1", meeting_time: meeting_time
      )

      expect { meeting_time.destroy! }.not_to change(GoogleCalendarEvent, :count)
      expect(event.reload.meeting_time_id).to be_nil
      expect(GoogleCalendarEvent.orphaned).to include(event)
    end

    it "is nullified, not destroyed, when its final exam is destroyed" do
      final_exam = FinalExam.create!(
        term: term, course: course, crn: 12345,
        exam_date: Date.new(2026, 12, 17),
        start_time: Time.zone.local(2026, 12, 17, 10, 0),
        end_time: Time.zone.local(2026, 12, 17, 12, 0)
      )
      event = calendar.google_calendar_events.create!(
        google_event_id: "evt_2", final_exam: final_exam
      )

      expect { final_exam.destroy! }.not_to change(GoogleCalendarEvent, :count)
      expect(event.reload.final_exam_id).to be_nil
      expect(GoogleCalendarEvent.orphaned).to include(event)
    end
  end
end
