# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseProcessorService do
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

  it "preserves calendar_events tracking rows across re-processing" do
    process!
    course = Course.find_by(crn: 12345)
    meeting_time = course.meeting_times.first

    credential = create(:oauth_credential, user: user)
    calendar = create(:course_calendar, oauth_credential: credential)
    event = create(:calendar_event, course_calendar: calendar, meeting_time: meeting_time)

    process!

    expect(event.reload.meeting_time_id).to eq(meeting_time.id)
  end

  it "removes meeting times that are no longer in the upload, nullifying their events" do
    process!
    course = Course.find_by(crn: 12345)

    credential = create(:oauth_credential, user: user)
    calendar = create(:course_calendar, oauth_credential: credential)
    stale_meeting_time = course.meeting_times.find_by(day_of_week: :wednesday)
    event = create(:calendar_event, course_calendar: calendar, meeting_time: stale_meeting_time)

    class_details[:meeting_times].first["days"] = { "monday" => true }
    process!

    expect(course.meeting_times.pluck(:day_of_week)).to eq([ "monday" ])
    expect(event.reload.meeting_time_id).to be_nil
    expect(CalendarEvent.orphaned).to include(event)
  end

  # Prosopite raises in Prosopite.scan when the same query runs once for each
  # course (#723).
  describe "with several courses" do
    let(:crns) { %w[11111 22222 33333] }
    let(:courses_payload) { crns.map { |crn| { crn: crn, term: "202710", courseNumber: "2000" } } }

    # Each section meets in its own building, so a lookup for each course
    # would send a different query each time.
    def details_for(crn)
      class_details.merge(
        meeting_times: [
          {
            "building"             => "ZQ#{crn.first}",
            "building_description" => "Hall #{crn.first}",
            "room"                 => "#{crn.first}01",
            "startDate"            => "09/08/2026",
            "endDate"              => "12/15/2026",
            "startTime"            => "1300",
            "endTime"              => "1445",
            "days"                 => { "monday" => true, "wednesday" => true }
          }
        ]
      )
    end

    before do
      allow(LeopardWebService).to receive(:get_class_details) { |course_reference_number:, **| details_for(course_reference_number) }
    end

    it "creates every course without one query for each course" do
      expect { Prosopite.scan { process! } }.not_to raise_error

      expect(user.enrollments.count).to eq(3)
      expect(Building.where(abbreviation: %w[ZQ1 ZQ2 ZQ3]).count).to eq(3)
    end

    it "updates every course without one query for each course" do
      process!
      classmate = create(:user)
      create(:course_calendar, oauth_credential: create(:oauth_credential, user: classmate))
      Course.where(crn: crns).find_each { |course| create(:enrollment, user: classmate, course: course, term: term) }

      allow(LeopardWebService).to receive(:get_class_details) { |course_reference_number:, **|
        details_for(course_reference_number).merge(title: "Algorithms")
      }
      expect { Prosopite.scan { process! } }.not_to raise_error

      expect(Course.where(crn: crns).pluck(:title)).to all(eq("Algorithms"))
      expect(classmate.reload.calendar_needs_sync).to be(true)
    end

    it "replaces moved meeting times and returns each course with its new times" do
      process!
      old_ids = Course::MeetingTime.where(course: Course.where(crn: crns)).ids

      result = nil
      allow(LeopardWebService).to receive(:get_class_details) { |course_reference_number:, **|
        details_for(course_reference_number).tap { |d| d[:meeting_times].first["startTime"] = "0900" }
      }
      expect { Prosopite.scan { result = process! } }.not_to raise_error

      expect(Course::MeetingTime.where(id: old_ids)).not_to exist
      expect(result.map { |c| c[:crn].to_s }).to eq(crns)
      expect(result.flat_map { |c| c[:meeting_times].pluck(:begin_time) }.uniq).to eq([ "9:00 AM" ])
    end

    it "attaches each course's instructors without one query for each course" do
      allow(LeopardWebService).to receive(:get_class_details) { |course_reference_number:, **|
        details_for(course_reference_number).merge(
          faculty: [
            { "displayName" => "Shared Teacher", "emailAddress" => "shared@example.edu", "primaryIndicator" => true },
            { "displayName" => "Teacher #{course_reference_number}", "emailAddress" => "t#{course_reference_number}@example.edu" }
          ]
        )
      }
      expect { Prosopite.scan { process! } }.not_to raise_error

      # The second run finds every instructor and join row already saved.
      expect { Prosopite.scan { process! } }.not_to raise_error

      expect(Course.where(crn: crns).map { |c| c.faculties.map(&:email) })
        .to all(include("shared@example.edu"))
      expect(Faculty.where(email: "shared@example.edu").count).to eq(1)
    end

    it "writes nothing when one course names an unknown term" do
      courses_payload << { crn: "44444", term: "209910", courseNumber: "2000" }

      expect { process! }.to raise_error(InvalidTermError)
      expect(Course.where(crn: crns)).not_to exist
    end
  end

  describe "instructors" do
    let(:banner_faculty) do
      [ { "displayName" => "Elijah Sanderson", "emailAddress" => "sandersone1@wit.edu",
          "primaryIndicator" => true } ]
    end

    it "attaches the instructor Banner reports" do
      allow(LeopardWebService).to receive(:get_class_details)
        .and_return(class_details.merge(faculty: banner_faculty))

      process!

      expect(Course.find_by(crn: 12345).faculties.map(&:email)).to eq([ "sandersone1@wit.edu" ])
    end

    it "prefers Banner over the name the extension posted" do
      allow(LeopardWebService).to receive(:get_class_details)
        .and_return(class_details.merge(faculty: banner_faculty))
      courses_payload.first.merge!(instructor: "Igor Minevich", instructorEmail: "minevichi@wit.edu")

      process!

      expect(Course.find_by(crn: 12345).faculties.map(&:email)).to eq([ "sandersone1@wit.edu" ])
    end

    it "drops an instructor Banner no longer lists on re-import" do
      allow(LeopardWebService).to receive(:get_class_details)
        .and_return(class_details.merge(faculty: [ { "displayName" => "Igor Minevich",
                                                     "emailAddress" => "minevichi@wit.edu" } ]))
      process!

      allow(LeopardWebService).to receive(:get_class_details)
        .and_return(class_details.merge(faculty: banner_faculty))
      process!

      expect(Course.find_by(crn: 12345).faculties.map(&:email)).to eq([ "sandersone1@wit.edu" ])
    end

    it "falls back to the posted instructor when Banner reports none" do
      courses_payload.first.merge!(instructor: "Igor Minevich", instructorEmail: "minevichi@wit.edu")

      process!

      expect(Course.find_by(crn: 12345).faculties.map(&:email)).to eq([ "minevichi@wit.edu" ])
    end

    it "records no instructor when the posted name carries no email" do
      courses_payload.first.merge!(instructor: "Igor Minevich")

      process!

      expect(Course.find_by(crn: 12345).faculties).to be_empty
      expect(Faculty.count).to eq(0)
    end
  end

  describe "fetching from Banner" do
    let(:courses_payload) do
      [ { crn: "12345", term: "202710", courseNumber: "2000" }, { crn: "67890", term: "202710", courseNumber: "2100" } ]
    end

    it "asks Banner about every section at the same time" do
      in_flight = Queue.new
      allow(LeopardWebService).to receive(:get_class_details) do |course_reference_number:, **|
        in_flight << course_reference_number
        # Hold this request open until the other one starts. Asked one after
        # another, the second never starts and this times out.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.01 while in_flight.size < 2 && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        raise "sections were fetched one at a time" if in_flight.size < 2

        class_details
      end

      process!

      expect(Course.where(term: term).pluck(:crn)).to contain_exactly(12345, 67890)
    end

    it "writes nothing when Banner fails for one section" do
      allow(LeopardWebService).to receive(:get_class_details).and_return(class_details)
      allow(LeopardWebService).to receive(:get_class_details)
        .with(term: "202710", course_reference_number: "67890")
        .and_raise(LeopardWebService::RequestError, "Banner is down")

      expect { process! }.to raise_error(LeopardWebService::RequestError)
      expect(Course.count).to eq(0)
    end
  end
end
