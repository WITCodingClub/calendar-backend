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
#  brightspace_assignment_id    :bigint
#  calendar_id                  :bigint           not null
#  external_event_id            :string           not null
#  final_exam_id                :bigint
#  meeting_time_id              :bigint
#  university_calendar_event_id :bigint
#
# Indexes
#
#  idx_calendar_events_on_calendar_id_meeting_time_id     (calendar_id,meeting_time_id)
#  idx_calendar_events_unique_brightspace_assignment      (calendar_id,brightspace_assignment_id) UNIQUE WHERE (brightspace_assignment_id IS NOT NULL)
#  idx_calendar_events_unique_final_exam                  (calendar_id,final_exam_id) UNIQUE WHERE (final_exam_id IS NOT NULL)
#  idx_calendar_events_unique_meeting_time                (calendar_id,meeting_time_id) UNIQUE WHERE (meeting_time_id IS NOT NULL)
#  idx_calendar_events_unique_university                  (calendar_id,university_calendar_event_id) UNIQUE WHERE (university_calendar_event_id IS NOT NULL)
#  index_calendar_events_on_brightspace_assignment_id     (brightspace_assignment_id)
#  index_calendar_events_on_external_event_id             (external_event_id)
#  index_calendar_events_on_external_ical_uid             (external_ical_uid)
#  index_calendar_events_on_final_exam_id                 (final_exam_id)
#  index_calendar_events_on_last_synced_at                (last_synced_at)
#  index_calendar_events_on_meeting_time_id               (meeting_time_id)
#  index_calendar_events_on_university_calendar_event_id  (university_calendar_event_id)
#
# Foreign Keys
#
#  fk_rails_...  (brightspace_assignment_id => brightspace_assignments.id)
#  fk_rails_...  (calendar_id => calendars.id)
#  fk_rails_...  (meeting_time_id => course_meeting_times.id)
#

require "rails_helper"

RSpec.describe CalendarEvent, type: :model do
  describe "associations and validations" do
    subject { create(:calendar_event) }

    it { is_expected.to belong_to(:course_calendar) }
    it { is_expected.to belong_to(:meeting_time).class_name("Course::MeetingTime").optional }
    it { is_expected.to belong_to(:final_exam).optional }
    it { is_expected.to belong_to(:university_calendar_event).optional }
    it { is_expected.to belong_to(:brightspace_assignment).class_name("Brightspace::Assignment").optional }
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

    context "associated with a Brightspace assignment instead" do
      subject { create(:calendar_event, :for_brightspace_assignment) }

      it { is_expected.to validate_uniqueness_of(:brightspace_assignment_id).scoped_to(:calendar_id) }
    end

    it "rejects an event with both a meeting time and an assignment" do
      event = build(:calendar_event, brightspace_assignment: create(:brightspace_assignment))

      expect(event).not_to be_valid
      expect(event.errors[:base].first).to include("brightspace_assignment")
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

      expect { event.destroy }.to have_enqueued_job(GoogleCalendarEventDeleteJob).with("cal_123", "google-evt")
    end

    it "deletes a Microsoft event with the owner's credential and its iCalUId" do
      event = create(:calendar_event, :microsoft, external_event_id: "AAMkSyntheticEvent1")

      expect { event.destroy }.to have_enqueued_job(MicrosoftGraphEventDeleteJob)
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

    it "is nullified, not destroyed, when its Brightspace assignment is destroyed" do
      event = create(:calendar_event, :for_brightspace_assignment, course_calendar: calendar)

      expect { event.brightspace_assignment.destroy! }.not_to change(CalendarEvent, :count)
      expect(event.reload.brightspace_assignment_id).to be_nil
      expect(CalendarEvent.orphaned).to include(event)
      expect(event).to be_orphaned
    end

    it "is not an orphan while its assignment exists" do
      event = create(:calendar_event, :for_brightspace_assignment, course_calendar: calendar)

      expect(CalendarEvent.orphaned).not_to include(event)
      expect(event.syncable).to eq(event.brightspace_assignment)
    end
  end
end
