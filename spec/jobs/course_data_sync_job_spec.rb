# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseDataSyncJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    Course.create!(
      crn: 12345, term: term, title: "Data Structures", subject: "COMP",
      course_number: 2000, section_number: "1", schedule_type: "LEC",
      credit_hours: 4, grade_mode: "Standard Letter",
      start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 15)
    )
  end

  # Banner's getFacultyMeetingTimes shape, as LeopardWebService returns it.
  def banner_meeting_time(building: "IRAH", description: "Ira Allen Hall", room: "112")
    {
      "building"             => building,
      "building_description" => description,
      "room"                 => room,
      "startDate"            => "09/08/2026",
      "endDate"              => "12/15/2026",
      "startTime"            => "1300",
      "endTime"              => "1445",
      "days"                 => { "monday" => true, "wednesday" => true }
    }
  end

  def banner_faculty(name: "Elijah Sanderson", email: "sandersone1@wit.edu")
    { "displayName" => name, "emailAddress" => email, "primaryIndicator" => true }
  end

  def class_details(meeting_times:, faculty: [])
    {
      title: "Data Structures",
      subject: "COMP",
      section_number: "01",
      schedule_type: "Lecture (LEC)",
      credit_hours: 4,
      grade_mode: "Standard Letter",
      seats_available: 5,
      seats_capacity: 30,
      meeting_times: meeting_times,
      faculty: faculty
    }
  end

  def stub_leopard_web(meeting_times, faculty: [])
    allow(LeopardWebService).to receive(:get_active_terms)
      .and_return({ success: true, terms: [ { code: term.uid.to_s, description: term.name } ] })
    allow(LeopardWebService).to receive(:get_class_details)
      .with(term: term.uid, course_reference_number: course.crn)
      .and_return(class_details(meeting_times: meeting_times, faculty: faculty))
  end

  def linked_rooms
    course.meeting_times.reload.flat_map { |mt| mt.rooms.map { |r| [ r.building.abbreviation, r.number ] } }.uniq
  end

  before do
    MeetingTimesIngestService.call(
      course: course,
      raw_meeting_times: MeetingTimesIngestService.normalize_leopard_web([ banner_meeting_time ])
    )
  end

  it "writes the new room when the registrar moves the section" do
    stub_leopard_web([ banner_meeting_time(room: "308") ])

    described_class.perform_now

    expect(linked_rooms).to eq([ [ "IRAH", "308" ] ])
  end

  it "writes the new building when the registrar moves the section" do
    stub_leopard_web([ banner_meeting_time(building: "BEAT", description: "Beatty Hall", room: "410") ])

    described_class.perform_now

    expect(linked_rooms).to eq([ [ "BEAT", "410" ] ])
  end

  it "clears the room when Banner no longer reports one" do
    stub_leopard_web([ banner_meeting_time(building: nil, description: nil, room: nil) ])

    described_class.perform_now

    expect(linked_rooms).to eq([ [ "TBD", "0" ] ])
  end

  it "reuses the meeting time rows so tracked calendar events stay attached" do
    ids_before = course.meeting_times.pluck(:id).sort
    stub_leopard_web([ banner_meeting_time(room: "308") ])

    described_class.perform_now

    expect(course.meeting_times.reload.pluck(:id).sort).to eq(ids_before)
  end

  it "keeps the stored meeting times when Banner returns none" do
    stub_leopard_web([])

    described_class.perform_now

    expect(course.meeting_times.reload.count).to eq(2)
    expect(linked_rooms).to eq([ [ "IRAH", "112" ] ])
  end

  describe "term selection" do
    it "syncs the running and upcoming terms, not every term Banner lists" do
      allow(LeopardWebService).to receive(:get_active_terms).and_raise("Banner should not be asked")
      allow(LeopardWebService).to receive(:get_class_details).and_return(nil)
      job = described_class.new

      expect(job.send(:default_term_uids)).to include(term.uid)
    end

    it "leaves out a term that has already ended" do
      old_term = Term.create!(
        uid: 201710, season: :fall, year: 2016,
        start_date: Date.new(2016, 9, 1), end_date: Date.new(2016, 12, 20)
      )

      expect(described_class.new.send(:default_term_uids)).not_to include(old_term.uid)
    end

    # Term.current picks by calendar month, not by whether classes are still
    # running, so it advances to the next term before the current one ends.
    # Term.current_and_future alone drops a still-running term twice a year.
    # These two cases are why default_term_uids unions in Term.active.
    context "when a running term overlaps the next one" do
      let!(:summer_2026) do
        Term.create!(uid: 202630, season: :summer, year: 2026,
                     start_date: Date.new(2026, 5, 18), end_date: Date.new(2026, 8, 20))
      end
      # The outer term is Fall 2026 (202710); it just needs real dates here.
      let!(:fall_2026) do
        term.tap { |t| t.update!(start_date: Date.new(2026, 9, 8), end_date: Date.new(2026, 12, 20)) }
      end
      let!(:spring_2027) do
        Term.create!(uid: 202720, season: :spring, year: 2027,
                     start_date: Date.new(2027, 1, 12), end_date: Date.new(2027, 5, 5))
      end

      it "keeps the fall term in December, after the heuristic jumps to spring" do
        travel_to(Date.new(2026, 12, 18)) do
          expect(Term.current_and_future.pluck(:uid)).not_to include(fall_2026.uid)
          expect(described_class.new.send(:default_term_uids)).to include(fall_2026.uid)
        end
      end

      it "keeps the summer term in August, while it is still in session" do
        travel_to(Date.new(2026, 8, 1)) do
          expect(Term.current_and_future.pluck(:uid)).not_to include(summer_2026.uid)
          expect(described_class.new.send(:default_term_uids)).to include(summer_2026.uid)
        end
      end
    end
  end

  describe "concurrency key" do
    it "accepts the job arguments so a scoped run can be enqueued" do
      expect { described_class.new(term_uids: [ 202710 ]).concurrency_key }.not_to raise_error
    end

    it "stays a single key regardless of the arguments" do
      expect(described_class.new(term_uids: [ 202710 ]).concurrency_key)
        .to eq(described_class.new.concurrency_key)
    end
  end

  context "when a student with a Google calendar is enrolled" do
    let(:user) { User.create!(email: "student@wit.edu", password: "password123") }
    let(:credential) do
      user.oauth_credentials.create!(
        provider: "google", uid: "google-uid", email: user.email, access_token: "token"
      )
    end
    # A user counts as having a calendar through this association, the same way
    # NightlyCalendarSyncJob selects them.
    let!(:google_calendar) { credential.create_google_calendar!(google_calendar_id: "cal_123") }
    let!(:enrollment) { Enrollment.create!(user: user, course: course, term: term) }

    before { user.update!(calendar_needs_sync: false) }

    it "marks the calendar for resync after a room-only change" do
      stub_leopard_web([ banner_meeting_time(room: "308") ])

      described_class.perform_now

      expect(user.reload.calendar_needs_sync).to be(true)
    end

    it "leaves the calendar alone when nothing changed" do
      stub_leopard_web([ banner_meeting_time ])

      described_class.perform_now

      expect(user.reload.calendar_needs_sync).to be(false)
    end
  end

  describe "instructor changes" do
    let(:previous_instructor) do
      Faculty.create!(email: "minevichi@wit.edu", first_name: "Igor", last_name: "Minevich")
    end

    before { course.faculties << previous_instructor }

    it "replaces the instructor when the registrar reassigns the section" do
      stub_leopard_web([ banner_meeting_time ], faculty: [ banner_faculty ])

      described_class.perform_now

      expect(course.reload.faculties.map(&:email)).to eq([ "sandersone1@wit.edu" ])
    end

    it "keeps the stored instructor when Banner reports none" do
      stub_leopard_web([ banner_meeting_time ], faculty: [])

      described_class.perform_now

      expect(course.reload.faculties.map(&:email)).to eq([ "minevichi@wit.edu" ])
    end
  end
end
