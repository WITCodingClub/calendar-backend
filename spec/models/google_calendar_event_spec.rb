# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendar_events
#
#  id                           :bigint           not null, primary key
#  end_time                     :datetime
#  event_data_hash              :string
#  last_synced_at               :datetime
#  location                     :string
#  recurrence                   :text
#  start_time                   :datetime
#  summary                      :string
#  user_edited_fields           :jsonb
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  final_exam_id                :bigint
#  google_calendar_id           :bigint           not null
#  google_event_id              :string           not null
#  meeting_time_id              :bigint
#  university_calendar_event_id :bigint
#
# Indexes
#
#  idx_gcal_events_unique_final_exam                             (google_calendar_id,final_exam_id) UNIQUE WHERE (final_exam_id IS NOT NULL)
#  idx_gcal_events_unique_meeting_time                           (google_calendar_id,meeting_time_id) UNIQUE WHERE (meeting_time_id IS NOT NULL)
#  idx_gcal_events_unique_university                             (google_calendar_id,university_calendar_event_id) UNIQUE WHERE (university_calendar_event_id IS NOT NULL)
#  idx_on_google_calendar_id_meeting_time_id                     (google_calendar_id,meeting_time_id)
#  index_google_calendar_events_on_final_exam_id                 (final_exam_id)
#  index_google_calendar_events_on_google_calendar_id            (google_calendar_id)
#  index_google_calendar_events_on_google_event_id               (google_event_id)
#  index_google_calendar_events_on_last_synced_at                (last_synced_at)
#  index_google_calendar_events_on_meeting_time_id               (meeting_time_id)
#  index_google_calendar_events_on_university_calendar_event_id  (university_calendar_event_id)
#
# Foreign Keys
#
#  fk_rails_...  (google_calendar_id => google_calendars.id)
#  fk_rails_...  (meeting_time_id => course_meeting_times.id)
#

require "rails_helper"

RSpec.describe GoogleCalendarEvent, type: :model do
  describe "associations and validations" do
    subject { create(:google_calendar_event) }

    it { is_expected.to belong_to(:google_calendar) }
    it { is_expected.to belong_to(:meeting_time).class_name("Course::MeetingTime").optional }
    it { is_expected.to belong_to(:final_exam).optional }
    it { is_expected.to belong_to(:university_calendar_event).optional }
    it { is_expected.to have_one(:event_preference).dependent(:destroy) }
    it { is_expected.to have_one(:oauth_credential).through(:google_calendar) }
    it { is_expected.to have_one(:user).through(:oauth_credential) }

    it { is_expected.to validate_presence_of(:google_event_id) }
    it { is_expected.to validate_uniqueness_of(:meeting_time_id).scoped_to(:google_calendar_id) }

    # #only_one_event_type_associated is a custom cross-field validation
    # (exactly one of meeting_time/final_exam/university_calendar_event), so
    # it has no single one-liner.

    context "associated with a final exam instead" do
      subject { create(:google_calendar_event, :for_final_exam) }

      it { is_expected.to validate_uniqueness_of(:final_exam_id).scoped_to(:google_calendar_id) }
    end

    context "associated with a university calendar event instead" do
      subject { create(:google_calendar_event, :for_university_event) }

      it { is_expected.to validate_uniqueness_of(:university_calendar_event_id).scoped_to(:google_calendar_id) }
    end
  end

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
