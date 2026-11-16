# frozen_string_literal: true

require "rails_helper"

RSpec.describe Courses::Reprocessor do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let!(:term) { create(:term, uid: 202710) }

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
          "days"                 => { "monday" => true }
        }
      ]
    }
  end

  let(:payload) { [ { crn: "12345", term: "202710", courseNumber: "2000" } ] }

  before do
    allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_return(class_details)
  end

  describe "input checks" do
    it "rejects nil courses" do
      expect { described_class.new(nil, user).call }.to raise_error(ArgumentError, "courses cannot be nil")
    end

    it "rejects courses that are not an array" do
      expect { described_class.new({ crn: "1" }, user).call }.to raise_error(ArgumentError, "courses must be an array")
    end

    it "rejects an empty array" do
      expect { described_class.new([], user).call }.to raise_error(ArgumentError, "courses cannot be empty")
    end

    it "rejects courses from more than one term" do
      mixed = [ { crn: "1", term: "202710" }, { "crn" => "2", "term" => "202720" } ]

      expect { described_class.new(mixed, user).call }.to raise_error(ArgumentError, "All courses must be from the same term")
    end

    it "rejects a term that does not exist" do
      unknown = [ { crn: "1", term: "209910" } ]

      expect { described_class.new(unknown, user).call }.to raise_error(ArgumentError, "Term with UID 209910 not found")
    end

    it "keeps the enrollments when the payload has more sections than the limit" do
      enrollment = create(:enrollment, user: user, course: create(:course, term: term, crn: 55555))
      too_many = Array.new(Courses::Processor::MAX_SECTIONS + 1) { |i| { crn: (20_000 + i).to_s, term: "202710" } }

      expect { described_class.new(too_many, user).call }.to raise_error(Courses::InvalidPayloadError)
      expect(Enrollment.exists?(enrollment.id)).to be(true)
    end
  end

  describe "#term_uid" do
    it "reads a string key" do
      expect(described_class.new([ { "term" => "202710" } ], user).term_uid).to eq("202710")
    end

    it "is nil when the first course is not a hash" do
      expect(described_class.new([ "x" ], user).term_uid).to be_nil
    end
  end

  describe "#call" do
    it "processes the new courses and flags the user for sync" do
      result = described_class.new(payload, user).call

      expect(result[:removed_enrollments]).to eq(0)
      expect(result[:removed_courses]).to eq([])
      expect(user.enrollments.joins(:course).where(courses: { crn: 12345 })).to exist
      expect(user.reload.calendar_needs_sync).to be(true)
    end

    it "keeps an enrollment whose crn is still in the list" do
      course = create(:course, term: term, crn: 12345)
      enrollment = create(:enrollment, user: user, course: course)

      result = described_class.new(payload, user).call

      expect(result[:removed_enrollments]).to eq(0)
      expect(Enrollment.exists?(enrollment.id)).to be(true)
    end

    context "when a course is no longer in the list" do
      let!(:old_course) { create(:course, term: term, crn: 55555, title: "Old Course", course_number: 1234) }
      let!(:old_enrollment) { create(:enrollment, user: user, course: old_course) }

      it "removes the enrollment and reports the course" do
        result = described_class.new(payload, user).call

        expect(Enrollment.exists?(old_enrollment.id)).to be(false)
        expect(result[:removed_enrollments]).to eq(1)
        expect(result[:removed_courses]).to eq([ { crn: 55555, title: "Old Course", course_number: 1234 } ])
      end

      it "leaves enrollments of other terms alone" do
        other_course = create(:course, term: create(:term, uid: 202720, year: 2027, season: :spring), crn: 66666)
        other_enrollment = create(:enrollment, user: user, course: other_course)

        described_class.new(payload, user).call

        expect(Enrollment.exists?(other_enrollment.id)).to be(true)
      end

      # The sync reconcile (CourseCalendars::Provider#update_calendar_events)
      # deletes the events of the removed course in every provider.
      it "queues the sync for the removed course when the processor fails" do
        create(:course_calendar, oauth_credential: create(:oauth_credential, user: user))
        allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_raise(Catalog::BannerThrottle::CooldownError.new(42))

        expect { described_class.new(payload, user).call }
          .to raise_error(Catalog::BannerThrottle::CooldownError)
          .and have_enqueued_job(CourseCalendars::SyncJob).with(user, force: false)
        expect(Enrollment.exists?(old_enrollment.id)).to be(false)
      end

      it "deletes the removed course's calendar event when the queued sync runs" do
        stub_google_service_account
        credential = create(:oauth_credential, user: user, token_expires_at: 1.hour.from_now)
        calendar   = create(:course_calendar, oauth_credential: credential, external_calendar_id: "reprocess-cal")
        row = create(:calendar_event, course_calendar: calendar, meeting_time: create(:course_meeting_time, course: old_course),
                                      external_event_id: "evt-old", start_time: 1.day.from_now, end_time: 1.day.from_now + 1.hour)
        delete = stub_request(:delete, %r{/calendars/reprocess-cal/events/evt-old}).to_return(status: 204)
        allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_raise(Catalog::BannerThrottle::CooldownError.new(42))

        perform_enqueued_jobs(only: CourseCalendars::SyncJob) do
          expect { described_class.new(payload, user).call }.to raise_error(Catalog::BannerThrottle::CooldownError)
        end

        expect(delete).to have_been_requested
        expect(CalendarEvent.exists?(row.id)).to be(false)
      end

      it "queues a sync for a user with a course calendar" do
        create(:course_calendar, oauth_credential: create(:oauth_credential, user: user))

        expect { described_class.new(payload, user).call }.to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: false)
      end
    end
  end
end
