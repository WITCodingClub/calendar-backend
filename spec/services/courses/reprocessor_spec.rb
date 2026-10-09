# frozen_string_literal: true

require "rails_helper"

RSpec.describe Courses::Reprocessor do
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

      context "with calendar events on the removed course" do
        let(:calendar_id) { "reprocess-cal" }
        let(:event_url) { %r{\Ahttps://www\.googleapis\.com/calendar/v3/calendars/reprocess-cal/events/} }
        let(:credential) { create(:oauth_credential, user: user, refresh_token: "synthetic-refresh", token_expires_at: 1.hour.from_now) }
        let(:calendar) { create(:course_calendar, oauth_credential: credential, external_calendar_id: calendar_id) }
        let(:meeting_time) { create(:course_meeting_time, course: old_course) }

        before do
          create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time, external_event_id: "evt-1")
        end

        it "deletes the events in Google and in the database" do
          stub = stub_request(:delete, "https://www.googleapis.com/calendar/v3/calendars/reprocess-cal/events/evt-1")
                 .to_return(status: 204)

          described_class.new(payload, user).call

          expect(stub).to have_been_requested
          expect(CalendarEvent.where(external_event_id: "evt-1")).to be_empty
        end

        it "still deletes the database row when Google answers with a client error" do
          stub_request(:delete, event_url).to_return(status: 404, body: { error: { message: "Not Found" } }.to_json,
                                                     headers: { "Content-Type" => "application/json" })

          described_class.new(payload, user).call

          expect(CalendarEvent.where(external_event_id: "evt-1")).to be_empty
        end

        it "refreshes an expired token before the delete" do
          credential.update!(token_expires_at: 1.hour.ago)
          token_stub = stub_request(:post, "https://oauth2.googleapis.com/token")
                       .to_return(status: 200,
                                  body: { access_token: "synthetic-new-token", expires_in: 3600 }.to_json,
                                  headers: { "Content-Type" => "application/json" })
          stub_request(:delete, event_url).to_return(status: 204)

          described_class.new(payload, user).call

          expect(token_stub).to have_been_requested
          expect(credential.reload.access_token).to eq("synthetic-new-token")
        end
      end

      it "skips the Google call when the user has no calendar" do
        create(:course_meeting_time, course: old_course)

        expect { described_class.new(payload, user).call }.not_to raise_error
      end

      it "skips the Google call when the course has no meeting times" do
        credential = create(:oauth_credential, user: user)
        create(:course_calendar, oauth_credential: credential)

        expect { described_class.new(payload, user).call }.not_to raise_error
        expect(Enrollment.exists?(old_enrollment.id)).to be(false)
      end

      it "skips the Google call when the meeting times have no events" do
        credential = create(:oauth_credential, user: user)
        create(:course_calendar, oauth_credential: credential)
        create(:course_meeting_time, course: old_course)

        expect { described_class.new(payload, user).call }.not_to raise_error
      end
    end
  end
end
