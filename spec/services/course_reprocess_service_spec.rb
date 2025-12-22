# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseReprocessService, type: :service do
  let(:user) { create(:user) }
  let(:term) { create(:term, uid: 202501, year: 2025, season: :spring) }

  before do
    # Stub LeopardWebService for course processing
    allow(LeopardWebService).to receive_messages(
      get_class_details: {
        associated_term: "Spring 2025",
        subject: "ENG",
        title: "English Composition",
        schedule_type: "Lecture (LEC)",
        section_number: "01",
        credit_hours: 3,
        grade_mode: "Normal"
      },
      get_faculty_meeting_times: {
        "fmt" => []
      }
    )
    # Stub calendar sync job
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
  end

  describe "#call" do
    context "validation" do
      it "raises error when courses is nil" do
        expect {
          described_class.new(nil, user).call
        }.to raise_error(ArgumentError, /courses cannot be nil/)
      end

      it "raises error when courses is not an array" do
        expect {
          described_class.new("not an array", user).call
        }.to raise_error(ArgumentError, /courses must be an array/)
      end

      it "raises error when courses is empty" do
        expect {
          described_class.new([], user).call
        }.to raise_error(ArgumentError, /courses cannot be empty/)
      end

      it "raises error when courses are from different terms" do
        courses = [
          { crn: 12345, term: 202501 },
          { crn: 67890, term: 202502 }
        ]

        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /All courses must be from the same term/)
      end

      it "raises error when term does not exist" do
        courses = [{ crn: 12345, term: 999999 }]

        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /Term with UID 999999 not found/)
      end
    end

    context "when user has no existing enrollments" do
      it "processes all courses as new" do
        courses = [
          { crn: 12345, term: term.uid, courseNumber: "ENG101", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        result = described_class.new(courses, user).call

        expect(result[:removed_enrollments]).to eq(0)
        expect(result[:removed_courses]).to be_empty
        expect(result[:processed_courses].count).to eq(1)
      end
    end

    context "when user has existing enrollments" do
      let!(:existing_course) { create(:course, crn: 11111, term: term, title: "Old English Course") }
      let!(:existing_enrollment) { create(:enrollment, user: user, course: existing_course, term: term) }

      it "removes enrollments not in the new course list" do
        # New course list does not include CRN 11111
        courses = [
          { crn: 22222, term: term.uid, courseNumber: "ENG102", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        result = described_class.new(courses, user).call

        expect(result[:removed_enrollments]).to eq(1)
        expect(result[:removed_courses].first[:crn]).to eq(11111)
        expect(user.enrollments.where(course: existing_course)).to be_empty
      end

      it "keeps enrollments that are still in the new course list" do
        # New course list includes the existing CRN
        courses = [
          { crn: 11111, term: term.uid, courseNumber: "ENG101", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        result = described_class.new(courses, user).call

        expect(result[:removed_enrollments]).to eq(0)
        expect(user.enrollments.where(course: existing_course)).to exist
      end

      it "handles mixed scenario - some removed, some kept, some added" do
        # Another existing enrollment
        kept_course = create(:course, crn: 22222, term: term, title: "Kept Course")
        create(:enrollment, user: user, course: kept_course, term: term)

        # New course list: keep 22222, add 33333, remove 11111
        courses = [
          { crn: 22222, term: term.uid, courseNumber: "MATH101", start: Time.zone.today, end: Time.zone.today + 90.days },
          { crn: 33333, term: term.uid, courseNumber: "CS101", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        result = described_class.new(courses, user).call

        expect(result[:removed_enrollments]).to eq(1)
        expect(result[:removed_courses].first[:crn]).to eq(11111)
        expect(user.enrollments.count).to eq(2)
        expect(user.enrollments.map { |e| e.course.crn }).to contain_exactly(22222, 33333)
      end
    end

    context "calendar event cleanup" do
      let(:credential) { create(:oauth_credential, user: user, provider: "google") }
      let(:google_calendar) { create(:google_calendar, oauth_credential: credential) }
      let(:existing_course) { create(:course, crn: 11111, term: term, title: "Course To Remove") }
      let!(:meeting_time) { create(:meeting_time, course: existing_course) }
      let!(:enrollment) { create(:enrollment, user: user, course: existing_course, term: term) }
      let!(:calendar_event) do
        create(:google_calendar_event,
               google_calendar: google_calendar,
               meeting_time: meeting_time,
               google_event_id: "test_event_123")
      end

      before do
        # Stub the GoogleCalendarService delete method
        allow_any_instance_of(GoogleCalendarService).to receive(:delete_event)
      end

      it "deletes calendar events for removed courses" do
        courses = [
          { crn: 22222, term: term.uid, courseNumber: "ENG102", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        expect_any_instance_of(GoogleCalendarService).to receive(:delete_event).with("test_event_123")

        result = described_class.new(courses, user).call

        expect(result[:removed_enrollments]).to eq(1)
        expect(GoogleCalendarEvent.find_by(id: calendar_event.id)).to be_nil
      end

      it "handles Google API errors gracefully and still removes local event" do
        courses = [
          { crn: 22222, term: term.uid, courseNumber: "ENG102", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        allow_any_instance_of(GoogleCalendarService).to receive(:delete_event)
          .and_raise(Google::Apis::ClientError.new("Not Found"))

        result = described_class.new(courses, user).call

        expect(result[:removed_enrollments]).to eq(1)
        expect(GoogleCalendarEvent.find_by(id: calendar_event.id)).to be_nil
      end
    end

    context "calendar sync triggering" do
      it "marks calendar as needing sync" do
        courses = [
          { crn: 12345, term: term.uid, courseNumber: "ENG101", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        described_class.new(courses, user).call

        expect(user.reload.calendar_needs_sync).to be true
      end
    end

    context "supports both symbol and string keys" do
      it "works with symbol keys" do
        courses = [
          { crn: 12345, term: term.uid, courseNumber: "ENG101", start: Time.zone.today, end: Time.zone.today + 90.days }
        ]

        result = described_class.new(courses, user).call
        expect(result[:processed_courses].count).to eq(1)
      end

      it "works with string keys" do
        courses = [
          { "crn" => 12345, "term" => term.uid, "courseNumber" => "ENG101", "start" => Time.zone.today.to_s, "end" => (Time.zone.today + 90.days).to_s }
        ]

        result = described_class.new(courses, user).call
        expect(result[:processed_courses].count).to eq(1)
      end
    end
  end
end
