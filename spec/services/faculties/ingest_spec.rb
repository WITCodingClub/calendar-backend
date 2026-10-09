# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::Ingest do
  let(:course) { create(:course) }

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
    existing = create(:faculty, email: "SandersonE1@wit.edu", first_name: "Elijah", last_name: "Sanderson")

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
    user = create(:user)
    create(:enrollment, user: user, course: course)
    credential = create(:oauth_credential, user: user)
    create(:course_calendar, oauth_credential: credential)
    user.update_column(:calendar_needs_sync, false)

    described_class.call(course: course, raw_faculty: [ sanderson ])

    expect(user.reload.calendar_needs_sync).to be(true)
  end

  # Prosopite raises in Prosopite.scan when the same query runs once for each
  # instructor (#729).
  describe "with several instructors" do
    let(:raw_faculty) do
      (1..3).map do |n|
        { "displayName" => "Teacher#{n} Example", "emailAddress" => "teacher#{n}@example.edu",
          "primaryIndicator" => n == 1 }
      end
    end

    it "attaches them without one query for each" do
      create(:faculty, email: "Teacher1@Example.edu")

      expect { Prosopite.scan { described_class.call(course: course, raw_faculty: raw_faculty) } }.not_to raise_error

      expect(course.reload.faculties.map(&:email))
        .to eq(%w[Teacher1@Example.edu teacher2@example.edu teacher3@example.edu])
    end

    it "updates them without one query for each" do
      described_class.call(course: course, raw_faculty: raw_faculty)
      moved = raw_faculty.map { |member| member.merge("primaryIndicator" => member["emailAddress"] == "teacher3@example.edu") }

      expect { Prosopite.scan { described_class.call(course: course.reload, raw_faculty: moved) } }.not_to raise_error

      expect(course.reload.faculties.first.email).to eq("teacher3@example.edu")
    end
  end

  describe ".preload" do
    it "matches an email in any case" do
      faculty = create(:faculty, email: "Mixed.Case@Example.edu")

      expect(described_class.preload([ [ { "displayName" => "Mixed Case", "emailAddress" => "mixed.case@example.edu" } ] ]))
        .to include("mixed.case@example.edu" => faculty)
    end
  end

  it "reads no instructor or join row when the caller passes them in" do
    raw = [ { "displayName" => "Cached Teacher", "emailAddress" => "cached@example.edu", "primaryIndicator" => true } ]
    described_class.call(course: course, raw_faculty: raw)
    faculty = described_class.preload([ raw ])
    joins = CourseFaculty.where(course: course).to_a

    queries = count_queries do
      described_class.call(course: course, raw_faculty: raw, faculty: faculty, existing_course_faculties: joins)
    end

    expect(queries).to eq(0)
  end
end
