# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_events
#
#  id                           :bigint           not null, primary key
#  end_time                     :datetime
#  event_data_hash              :string
#  external_ical_uid            :string
#  last_synced_at               :datetime
#  location                     :string
#  recurrence                   :text
#  start_time                   :datetime
#  summary                      :string
#  user_edited_fields           :jsonb
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  calendar_id                  :bigint           not null
#  external_event_id            :string           not null
#  final_exam_id                :bigint
#  friend_meeting_id            :bigint
#  meeting_time_id              :bigint
#  university_calendar_event_id :bigint
#
# Indexes
#
#  idx_calendar_events_on_calendar_id_meeting_time_id     (calendar_id,meeting_time_id)
#  idx_calendar_events_unique_final_exam                  (calendar_id,final_exam_id) UNIQUE WHERE (final_exam_id IS NOT NULL)
#  idx_calendar_events_unique_friend_meeting              (calendar_id,friend_meeting_id) UNIQUE WHERE (friend_meeting_id IS NOT NULL)
#  idx_calendar_events_unique_meeting_time                (calendar_id,meeting_time_id) UNIQUE WHERE (meeting_time_id IS NOT NULL)
#  idx_calendar_events_unique_university                  (calendar_id,university_calendar_event_id) UNIQUE WHERE (university_calendar_event_id IS NOT NULL)
#  index_calendar_events_on_external_event_id             (external_event_id)
#  index_calendar_events_on_external_ical_uid             (external_ical_uid)
#  index_calendar_events_on_final_exam_id                 (final_exam_id)
#  index_calendar_events_on_friend_meeting_id             (friend_meeting_id)
#  index_calendar_events_on_last_synced_at                (last_synced_at)
#  index_calendar_events_on_meeting_time_id               (meeting_time_id)
#  index_calendar_events_on_university_calendar_event_id  (university_calendar_event_id)
#
# Foreign Keys
#
#  fk_rails_...  (calendar_id => calendars.id)
#  fk_rails_...  (final_exam_id => final_exams.id) ON DELETE => nullify
#  fk_rails_...  (friend_meeting_id => friend_meetings.id)
#  fk_rails_...  (meeting_time_id => course_meeting_times.id)
#  fk_rails_...  (university_calendar_event_id => university_calendar_events.id) ON DELETE => nullify
#

require "rails_helper"

RSpec.describe CalendarEvent, type: :model do
  describe "associations and validations" do
    subject { create(:calendar_event) }

    it { is_expected.to belong_to(:course_calendar) }
    it { is_expected.to belong_to(:meeting_time).class_name("Course::MeetingTime").optional }
    it { is_expected.to belong_to(:final_exam).optional }
    it { is_expected.to belong_to(:university_calendar_event).optional }
    it { is_expected.to belong_to(:friend_meeting).optional }
    it { is_expected.to have_one(:event_preference).dependent(:destroy) }
    it { is_expected.to have_one(:oauth_credential).through(:course_calendar) }
    it { is_expected.to have_one(:user).through(:oauth_credential) }

    it { is_expected.to validate_presence_of(:external_event_id) }
    it { is_expected.to validate_uniqueness_of(:meeting_time_id).scoped_to(:calendar_id) }

    # #only_one_event_type_associated is a custom cross-field validation
    # (exactly one of meeting_time/final_exam/university_calendar_event), so
    # it has no single one-liner.

    context "associated with a final exam instead" do
      subject { create(:calendar_event, :for_final_exam) }

      it { is_expected.to validate_uniqueness_of(:final_exam_id).scoped_to(:calendar_id) }
    end

    context "associated with a university calendar event instead" do
      subject { create(:calendar_event, :for_university_event) }

      it { is_expected.to validate_uniqueness_of(:university_calendar_event_id).scoped_to(:calendar_id) }
    end

    context "associated with a friend meeting instead" do
      subject { create(:calendar_event, :for_friend_meeting) }

      it { is_expected.to validate_uniqueness_of(:friend_meeting_id).scoped_to(:calendar_id) }
    end
  end

  describe "event type check" do
    it "refuses a row with a meeting time and a friend meeting" do
      event = build(:calendar_event, friend_meeting: create(:friend_meeting))

      expect(event).not_to be_valid
      expect(event.errors[:base].first).to include("friend_meeting")
    end
  end

  let(:user)       { create(:user) }
  let(:credential) { create(:oauth_credential, user: user) }
  let(:calendar)   { create(:course_calendar, oauth_credential: credential, external_calendar_id: "cal_123") }

  let(:term)   { create(:term) }
  let(:course) { create(:course, term: term) }

  describe "remote deletion on destroy" do
    include ActiveJob::TestHelper

    it "deletes a Google event through the service account job" do
      event = create(:calendar_event, course_calendar: calendar, external_event_id: "google-evt")

      expect { event.destroy }.to have_enqueued_job(GoogleCalendar::EventDeleteJob).with("cal_123", "google-evt")
    end

    it "deletes a Microsoft event with the owner's credential and its iCalUId" do
      event = create(:calendar_event, :microsoft, external_event_id: "AAMkSyntheticEvent1")

      expect { event.destroy }.to have_enqueued_job(MicrosoftGraph::EventDeleteJob)
        .with(event.course_calendar.oauth_credential_id, "AAMkSyntheticEvent1", event.external_ical_uid)
    end

    it "leaves the remote event alone when the sync already deleted it" do
      event = create(:calendar_event, course_calendar: calendar)
      event.skip_remote_deletion = true

      expect { event.destroy }.not_to have_enqueued_job
    end
  end

  describe "orphaning behavior" do
    it "is nullified, not destroyed, when its meeting time is destroyed" do
      meeting_time = create(:course_meeting_time, course: course)
      event = create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time)

      expect { meeting_time.destroy! }.not_to change(CalendarEvent, :count)
      expect(event.reload.meeting_time_id).to be_nil
      expect(CalendarEvent.orphaned).to include(event)
    end

    it "is nullified, not destroyed, when its final exam is destroyed" do
      final_exam = create(:final_exam, term: term, course: course)
      event = create(:calendar_event, :for_final_exam, course_calendar: calendar, final_exam: final_exam)

      expect { final_exam.destroy! }.not_to change(CalendarEvent, :count)
      expect(event.reload.final_exam_id).to be_nil
      expect(CalendarEvent.orphaned).to include(event)
    end

    it "does not count a friend meeting row as orphaned" do
      event = create(:calendar_event, :for_friend_meeting, course_calendar: calendar)

      expect(CalendarEvent.orphaned).not_to include(event)
      expect(event).not_to be_orphaned
      expect(event.syncable).to eq(event.friend_meeting)
    end
  end

  describe ".schedule_events and .friend_meetings_only" do
    it "splits the rows that a course sync owns from friend meeting rows" do
      course_row  = create(:calendar_event, course_calendar: calendar)
      meeting_row = create(:calendar_event, :for_friend_meeting, course_calendar: calendar)

      expect(CalendarEvent.schedule_events).to contain_exactly(course_row)
      expect(CalendarEvent.friend_meetings_only).to contain_exactly(meeting_row)
    end
  end

  describe "friend meeting removal" do
    include ActiveJob::TestHelper

    it "deletes the remote event when the meeting is destroyed" do
      event = create(:calendar_event, :for_friend_meeting, course_calendar: calendar, external_event_id: "google-meeting")

      expect { event.friend_meeting.destroy }.to have_enqueued_job(GoogleCalendar::EventDeleteJob).with("cal_123", "google-meeting")
      expect(CalendarEvent.exists?(event.id)).to be(false)
    end

    # A Microsoft meeting is in the primary calendar, so deleting the app's
    # own calendar does not remove it.
    it "deletes a Microsoft meeting event on its own when its separate course calendar goes" do
      event = create(:calendar_event, :microsoft, :for_friend_meeting, external_event_id: "AAMkSyntheticMeeting1")

      expect { event.course_calendar.destroy }.to have_enqueued_job(MicrosoftGraph::EventDeleteJob)
        .with(event.course_calendar.oauth_credential_id, "AAMkSyntheticMeeting1", event.external_ical_uid)
    end

    it "leaves a Google meeting event to the calendar delete" do
      event = create(:calendar_event, :for_friend_meeting, course_calendar: calendar)

      expect { calendar.destroy }.not_to have_enqueued_job(GoogleCalendar::EventDeleteJob)
      expect(CalendarEvent.exists?(event.id)).to be(false)
    end
  end
end
