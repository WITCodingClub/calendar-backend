# frozen_string_literal: true

require "rails_helper"

# Issue #449: the plan courses of the term a student registers for next.
RSpec.describe AcademicProfiles::NextTermCourses do
  let(:user) { create(:user) }
  let(:today) { Date.new(2026, 11, 6) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let(:set) { create(:requirement_set, degree_program: major, catalog_year: catalog_year) }
  let(:plan) { create(:program_plan, requirement_set: set) }
  let(:past_term) { create(:term, year: 2025, season: :fall, end_date: Date.new(2025, 12, 20)) }
  let(:current_term) { create(:term, year: 2026, season: :fall, end_date: Date.new(2026, 12, 20)) }
  # Spring 2027: year 2, spring of a Fall 2025 start.
  let(:spring_uid) { 202720 }

  before do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)
  end

  def result(term_uid: spring_uid) = described_class.new(user, term_uid: term_uid, today: today).call

  def item(kind = nil, year: 2, season: "spring", **attributes)
    create(:program_plan_item, *[ kind ].compact, program_plan: plan, year_index: year, season: season, **attributes)
  end

  def take(term, subject, number, outcome: nil)
    course = create(:course, term: term, subject: subject, course_number: number)
    create(:enrollment, user: user, course: course)
    create(:course_outcome, user: user, course: course, outcome: outcome) if outcome
  end

  def requires(subject, number, tree)
    create(:catalog_course, subject_code: subject, course_number: number, prerequisites: tree)
  end

  def course_leaf(subject, number, min_grade: nil)
    { "type" => "course", "subject_code" => subject, "course_number" => number, "min_grade" => min_grade }.compact
  end

  def program = result[:programs].first

  it "lists the open rows of the plan semester in the term, and earlier open rows as behind" do
    item(year: 1, season: "fall", subject_code: "WDGT", course_number: 1000)
    item(year: 1, season: "spring", subject_code: "WDGT", course_number: 1100)
    item(year: 2, season: "fall", subject_code: "WDGT", course_number: 2000)
    item(subject_code: "WDGT", course_number: 2100)
    item(subject_code: "WDGT", course_number: 2200)
    item(year: 3, season: "fall", subject_code: "WDGT", course_number: 3000)
    take(past_term, "WDGT", 1000)
    take(current_term, "WDGT", 2000)
    take(current_term, "WDGT", 2200)

    expect(result[:term]).to eq(uid: spring_uid, name: "Spring 2027")
    expect(program).to include(program: "widget-design-bs", plan: "Four Year Program", start_term: "Fall 2025",
                               semester: { year: 2, season: "spring" })
    expect(program[:planned].pluck(:code)).to eq([ "WDGT 2100" ])
    expect(program[:behind].pluck(:code, :year, :season)).to eq([ [ "WDGT 1100", 1, "spring" ] ])
  end

  it "names each option of a choice, and no course for an elective slot" do
    item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 2100 },
                             { "subject_code" => "WDGT", "course_number" => 2150 } ])
    item(:placeholder, label: "Free Elective")

    rows = program[:planned]
    expect(rows.first[:courses].pluck(:code)).to eq([ "WDGT 2100", "WDGT 2150" ])
    expect(rows.last).to include(kind: "placeholder", label: "Free Elective", courses: [])
  end

  it "says if the term has a section, and nothing when the term has no sections yet" do
    item(subject_code: "WDGT", course_number: 2100)
    item(subject_code: "WDGT", course_number: 2200)

    expect(result[:sections]).to be(false)
    expect(program[:planned].first[:courses].first[:offered]).to be_nil

    spring = create(:term, uid: spring_uid, year: 2027, season: :spring)
    create(:course, term: spring, subject: "WDGT", course_number: 2100)
    create(:course, term: spring, subject: "WDGT", course_number: 2200, status: "cancelled")

    expect(result[:sections]).to be(true)
    expect(program[:planned].map { |row| row[:courses].first[:offered] }).to eq([ true, false ])
  end

  it "checks prerequisites with the courses done or in progress, and lists the missing ones" do
    item(subject_code: "WDGT", course_number: 2100)
    item(subject_code: "WDGT", course_number: 2200)
    item(subject_code: "WDGT", course_number: 2300)
    item(subject_code: "WDGT", course_number: 2400)
    requires("WDGT", 2100, { "type" => "and", "operands" => [ course_leaf("WDGT", 1000), course_leaf("WDGT", 2000) ] })
    requires("WDGT", 2200, { "type" => "or", "operands" => [ course_leaf("WDGT", 1100), course_leaf("WDGT", 1200) ] })
    requires("WDGT", 2300, { "type" => "test", "name" => "WIT Math Assessment", "score" => "1500" })
    create(:catalog_course, subject_code: "WDGT", course_number: 2400, title: "Widget Studio")
    take(past_term, "WDGT", 1000)
    take(current_term, "WDGT", 2000)

    courses = program[:planned].map { |row| row[:courses].first }
    expect(courses.pluck(:code, :prerequisites, :missing)).to eq([
      [ "WDGT 2100", "met", [] ],
      [ "WDGT 2200", "not_met", [ "WDGT 1100", "WDGT 1200" ] ],
      [ "WDGT 2300", "unknown", [] ],
      [ "WDGT 2400", nil, [] ]
    ])
    expect(courses.last[:title]).to eq("Widget Studio")
  end

  it "does not count a D for a prerequisite with a minimum grade of C, and counts an alias of the course" do
    item(subject_code: "WDGT", course_number: 2100)
    item(subject_code: "WDGT", course_number: 2200)
    requires("WDGT", 2100, course_leaf("WDGT", 1000, min_grade: "C"))
    requires("WDGT", 2200, course_leaf("WDGT", 1050))
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 105, to_subject_code: "WDGT", to_course_number: 1050)
    take(past_term, "WDGT", 1000, outcome: "passed_below_c")
    take(past_term, "WDGT", 105)

    expect(program[:planned].map { |row| row[:courses].first[:prerequisites] }).to eq(%w[not_met met])
  end

  it "has no plan semester and no rows when the term is after the end of the plan" do
    item(year: 1, season: "fall", subject_code: "WDGT", course_number: 1000)
    take(past_term, "WDGT", 1000)

    expect(result(term_uid: 203020)[:programs].first).to include(semester: nil, planned: [], behind: [])
  end

  it "skips a program with no plan of study" do
    minor = create(:degree_program, :minor, slug: "gear-minor")
    create(:requirement_set, degree_program: minor, catalog_year: catalog_year)
    create(:student_program, user: user, degree_program: minor, catalog_year: catalog_year, role: "minor")
    item(subject_code: "WDGT", course_number: 2100)

    expect(result[:programs].pluck(:program)).to eq([ "widget-design-bs" ])
  end

  it "has no rows when the start term is not known" do
    user.student_programs.update_all(catalog_term_uid: nil) # rubocop:disable Rails/SkipsModelValidations
    item(subject_code: "WDGT", course_number: 2100)

    expect(program).to include(start_term: nil, semester: nil, planned: [], behind: [])
  end

  describe ".default_term_uid" do
    it "is the spring after a fall term, and the fall after a spring or summer term" do
      expect(described_class.default_term_uid(202710)).to eq(202720)
      expect(described_class.default_term_uid(202720)).to eq(202810)
      expect(described_class.default_term_uid(202730)).to eq(202810)
      expect(described_class.default_term_uid(nil)).to be_nil
    end
  end
end
