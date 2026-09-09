# frozen_string_literal: true

require "rails_helper"

RSpec.describe FacultyIngestService do
  let(:term) { Term.create!(uid: 202710, season: :fall, year: 2026) }
  let(:course) do
    Course.create!(
      crn: 16004,
      term: term,
      title: "Calculus 2A",
      subject: "MATH",
      course_number: 1876,
      section_number: "03",
      schedule_type: "LEC",
      start_date: Date.new(2026, 9, 8),
      end_date: Date.new(2026, 10, 20)
    )
  end

  let(:sanderson) do
    {
      "displayName"      => "Elijah Sanderson",
      "emailAddress"     => "sandersone1@wit.edu",
      "primaryIndicator" => true
    }
  end

  let(:minevich) do
    {
      "displayName"      => "Igor Minevich",
      "emailAddress"     => "minevichi@wit.edu",
      "primaryIndicator" => true
    }
  end

  it "attaches the instructor Banner reports" do
    expect(described_class.call(course: course, raw_faculty: [ sanderson ])).to be(true)

    expect(course.faculties.map(&:email)).to eq([ "sandersone1@wit.edu" ])
  end

  it "detaches an instructor Banner no longer lists" do
    described_class.call(course: course, raw_faculty: [ minevich ])

    expect(described_class.call(course: course, raw_faculty: [ sanderson ])).to be(true)

    expect(course.reload.faculties.map(&:email)).to eq([ "sandersone1@wit.edu" ])
  end

  it "orders the primary instructor first regardless of insert order" do
    described_class.call(
      course: course,
      raw_faculty: [
        minevich.merge("primaryIndicator" => false),
        sanderson
      ]
    )

    expect(course.reload.faculties.map(&:email))
      .to eq([ "sandersone1@wit.edu", "minevichi@wit.edu" ])
  end

  it "moves the primary flag when Banner moves it" do
    described_class.call(
      course: course,
      raw_faculty: [ sanderson, minevich.merge("primaryIndicator" => false) ]
    )

    changed = described_class.call(
      course: course,
      raw_faculty: [ sanderson.merge("primaryIndicator" => false), minevich ]
    )

    expect(changed).to be(true)
    expect(course.reload.faculties.map(&:email))
      .to eq([ "minevichi@wit.edu", "sandersone1@wit.edu" ])
  end

  it "reports no change when the roster is already correct" do
    described_class.call(course: course, raw_faculty: [ sanderson ])

    expect(described_class.call(course: course, raw_faculty: [ sanderson ])).to be(false)
  end

  it "keeps the existing roster when Banner answers with nothing" do
    described_class.call(course: course, raw_faculty: [ sanderson ])

    expect(described_class.call(course: course, raw_faculty: [])).to be(false)
    expect(course.reload.faculties.count).to eq(1)
  end

  it "reuses a faculty record whose stored email differs only in case" do
    existing = Faculty.create!(
      email: "SandersonE1@wit.edu",
      first_name: "Elijah",
      last_name: "Sanderson"
    )

    described_class.call(course: course, raw_faculty: [ sanderson ])

    expect(course.faculties.map(&:id)).to eq([ existing.id ])
    expect(Faculty.count).to eq(1)
  end

  it "accepts the catalog's 'Last, First' display name" do
    described_class.call(
      course: course,
      raw_faculty: [ { "displayName" => "Sanderson, Elijah", "emailAddress" => "sandersone1@wit.edu" } ]
    )

    faculty = course.faculties.first
    expect(faculty.first_name).to eq("Elijah")
    expect(faculty.last_name).to eq("Sanderson")
  end

  it "skips entries with no email rather than inventing one" do
    expect(
      described_class.call(course: course, raw_faculty: [ { "displayName" => "Elijah Sanderson" } ])
    ).to be(false)

    expect(course.faculties).to be_empty
  end

  it "marks enrolled users for calendar sync when the instructor changes" do
    user = User.create!(
      email: "student@wit.edu",
      password: "password123",
      first_name: "Leigh",
      last_name: "Student"
    )
    Enrollment.create!(user: user, course: course, term: term)
    credential = user.oauth_credentials.create!(
      provider: "google",
      uid: "google-uid-1",
      email: "student@wit.edu",
      access_token: "token"
    )
    credential.create_google_calendar!(google_calendar_id: "cal-1", summary: "WIT-Calendar")
    user.update_column(:calendar_needs_sync, false)

    described_class.call(course: course, raw_faculty: [ sanderson ])

    expect(user.reload.calendar_needs_sync).to be(true)
  end
end
