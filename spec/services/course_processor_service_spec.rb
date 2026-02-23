# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseProcessorService, type: :service do
  let(:user) { create(:user) }
  let(:term) { create(:term, uid: 202610, year: 2025, season: :fall) }

  let(:base_class_details) do
    {
      associated_term: "Fall 2025",
      subject: "CS",
      title: "Intro to CS",
      schedule_type: "Lecture (LEC)",
      section_number: "01",
      credit_hours: 3,
      grade_mode: "Normal",
      seats_available: 10,
      seats_capacity: 25
    }
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

      it "raises error when course is not a hash" do
        courses = ["not a hash"]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /must be a hash/)
      end

      it "raises error when crn is missing" do
        courses = [{ term: 202610 }]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /missing required field: crn/)
      end

      it "raises error when term is missing" do
        courses = [{ crn: 12345 }]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /missing required field: term/)
      end

      it "raises error when term UID is not numeric" do
        courses = [{ crn: 12345, term: "invalid" }]
        expect {
          described_class.new(courses, user).call
        }.to raise_error(ArgumentError, /invalid term UID/)
      end
    end

    context "term lookup" do
      it "raises InvalidTermError when term does not exist" do
        courses = [{ crn: 12345, term: 999999 }]

        # Mock LeopardWebService to prevent actual HTTP calls
        allow(LeopardWebService).to receive(:get_class_details).and_return({})

        expect {
          described_class.new(courses, user).call
        }.to raise_error(InvalidTermError) do |error|
          expect(error.uid).to eq(999999)
          expect(error.message).to include("Term with UID 999999 not found")
        end
      end

      it "successfully finds term when it exists" do
        courses = [{
          crn: 12345,
          term: term.uid,
          start: Time.zone.today,
          end: Time.zone.today + 90.days,
          courseNumber: "CS101"
        }]

        allow(LeopardWebService).to receive_messages(get_class_details: base_class_details,
                                                     get_faculty_meeting_times: { "fmt" => [] })

        expect {
          described_class.new(courses, user).call
        }.not_to raise_error
      end
    end

    context "deduplication" do
      before do
        allow(LeopardWebService).to receive_messages(get_class_details: base_class_details,
                                                     get_faculty_meeting_times: { "fmt" => [] })
      end

      it "deduplicates courses by CRN and term" do
        courses = [
          { crn: 12345, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" },
          { crn: 12345, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" },
          { crn: 12345, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" }
        ]

        # Should only call LeopardWebService once
        expect(LeopardWebService).to receive(:get_class_details).once

        result = described_class.new(courses, user).call
        expect(result.length).to eq(1)
      end
    end

    context "credit hours" do
      it "sets lab courses to 0 credit hours" do
        courses = [
          { crn: 12345, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" }
        ]

        allow(LeopardWebService).to receive_messages(get_class_details: base_class_details.merge(
          title: "Computer Science I - Lab",
          schedule_type: "Laboratory (LAB)",
          credit_hours: 4 # LeopardWeb incorrectly returns total course credits
        ), get_faculty_meeting_times: { "fmt" => [] })

        described_class.new(courses, user).call

        course = Course.find_by(crn: 12345)
        expect(course.credit_hours).to eq(0)
        expect(course.schedule_type).to eq("laboratory")
      end

      it "keeps lecture courses with original credit hours" do
        courses = [
          { crn: 12346, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" }
        ]

        allow(LeopardWebService).to receive_messages(get_class_details: base_class_details.merge(
          title: "Computer Science I",
          credit_hours: 4
        ), get_faculty_meeting_times: { "fmt" => [] })

        described_class.new(courses, user).call

        course = Course.find_by(crn: 12346)
        expect(course.credit_hours).to eq(4)
        expect(course.schedule_type).to eq("lecture")
      end

      it "keeps hybrid courses with original credit hours" do
        courses = [
          { crn: 12347, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS201" }
        ]

        allow(LeopardWebService).to receive_messages(get_class_details: base_class_details.merge(
          title: "Advanced Programming",
          schedule_type: "Hybrid (HYB)",
          credit_hours: 3
        ), get_faculty_meeting_times: { "fmt" => [] })

        described_class.new(courses, user).call

        course = Course.find_by(crn: 12347)
        expect(course.credit_hours).to eq(3)
        expect(course.schedule_type).to eq("hybrid")
      end
    end

    context "seat counts" do
      let(:courses) do
        [{ crn: 12345, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" }]
      end

      it "sets seats_available and seats_capacity on new courses" do
        allow(LeopardWebService).to receive_messages(
          get_class_details: base_class_details.merge(seats_available: 7, seats_capacity: 25),
          get_faculty_meeting_times: { "fmt" => [] }
        )

        described_class.new(courses, user).call

        course = Course.find_by(crn: 12345)
        expect(course.seats_available).to eq(7)
        expect(course.seats_capacity).to eq(25)
      end

      it "updates seats on an existing course (enrollment changes frequently)" do
        existing_course = create(:course, crn: 12345, term: term, seats_available: 20, seats_capacity: 25)

        allow(LeopardWebService).to receive_messages(
          get_class_details: base_class_details.merge(seats_available: 3, seats_capacity: 25),
          get_faculty_meeting_times: { "fmt" => [] }
        )

        described_class.new(courses, user).call

        expect(existing_course.reload.seats_available).to eq(3)
      end

      it "handles nil seat data gracefully (enrollment info unavailable)" do
        allow(LeopardWebService).to receive_messages(
          get_class_details: base_class_details.merge(seats_available: nil, seats_capacity: nil),
          get_faculty_meeting_times: { "fmt" => [] }
        )

        expect {
          described_class.new(courses, user).call
        }.not_to raise_error
      end
    end

    context "calendar sync" do
      before do
        allow(LeopardWebService).to receive_messages(get_class_details: base_class_details,
                                                     get_faculty_meeting_times: { "fmt" => [] })
      end

      it "enqueues GoogleCalendarSyncJob when user has google calendar" do
        # Create a Google credential with a calendar
        credential = create(:oauth_credential, user: user, provider: "google")
        create(:google_calendar, oauth_credential: credential)

        courses = [
          { crn: 12345, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" }
        ]

        expect {
          described_class.new(courses, user).call
        }.to have_enqueued_job(GoogleCalendarSyncJob).with(user, force: false)
      end

      it "does not enqueue GoogleCalendarSyncJob when user has no google calendar" do
        courses = [
          { crn: 12345, term: term.uid, start: Time.zone.today, end: Time.zone.today + 90.days, courseNumber: "CS101" }
        ]

        expect {
          described_class.new(courses, user).call
        }.not_to have_enqueued_job(GoogleCalendarSyncJob)
      end
    end
  end
end
