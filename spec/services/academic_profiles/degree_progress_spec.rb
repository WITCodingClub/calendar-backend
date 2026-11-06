# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::DegreeProgress do
  let(:user) { create(:user) }
  let(:today) { Date.new(2026, 11, 6) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let(:set) { create(:requirement_set, degree_program: major, catalog_year: catalog_year, name: "Widget Design, B.S.") }
  let(:plan) { create(:program_plan, requirement_set: set) }
  let(:past_term) { create(:term, year: 2025, season: :fall, end_date: Date.new(2025, 12, 20)) }
  let(:current_term) { create(:term, year: 2026, season: :fall, end_date: Date.new(2026, 12, 20)) }

  def progress(**arguments) = described_class.new(user, today: today, **arguments).call

  def take(term, subject, number, outcome: nil, credits: 4)
    course = create(:course, term: term, subject: subject, course_number: number, credit_hours: credits)
    create(:enrollment, user: user, course: course)
    create(:course_outcome, user: user, course: course, outcome: outcome) if outcome
    course
  end

  def item(kind = nil, **attributes)
    create(:program_plan_item, *[ kind ].compact, program_plan: plan, **attributes)
  end

  def statuses(result) = result[:programs].first[:requirements].map { |row| [ row[:code] || row[:label], row[:status] ] }

  before { create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610) }

  it "says how to add a program when the student has none with a catalog link, and does not guess" do
    user.student_programs.update_all(degree_program_id: nil) # rubocop:disable Rails/SkipsModelValidations

    expect { progress }.to raise_error(described_class::NoProgramError, /process a term/)
  end

  it "skips a program whose catalog year is not imported" do
    catalog_year.update!(status: "pending")

    expect { progress }.to raise_error(described_class::NoProgramError)
  end

  it "marks required courses done, in progress, or open from the courses and outcomes" do
    item(subject_code: "WDGT", course_number: 1000)
    item(subject_code: "WDGT", course_number: 1100)
    item(subject_code: "WDGT", course_number: 1200)
    item(subject_code: "WDGT", course_number: 1300)
    take(past_term, "WDGT", 1000)
    take(current_term, "WDGT", 1100)
    take(past_term, "WDGT", 1200, outcome: "failed")

    result = progress

    expect(statuses(result)).to eq([ [ "WDGT 1000", "done" ], [ "WDGT 1100", "in_progress" ], [ "WDGT 1200", "open" ],
                                     [ "WDGT 1300", "open" ] ])
    program = result[:programs].first
    expect(program).to include(program: "widget-design-bs", catalog_year: "2025-2026", plan: "Four Year Program",
                               counts: { "done" => 1, "in_progress" => 1, "open" => 2 })
    expect(program[:open].pluck(:code)).to eq([ "WDGT 1100", "WDGT 1200", "WDGT 1300" ])
    expect(result[:courses].find { |course| course[:code] == "WDGT 1200" }).to include(status: "not_passed", outcome: "failed")
    expect(result[:assumptions]).to include(a_string_including("past term with no outcome from LeopardWeb counts as passed"))
  end

  it "counts a passed outcome in the current term as done, and a D as done" do
    item(subject_code: "WDGT", course_number: 1000)
    item(subject_code: "WDGT", course_number: 1100)
    take(current_term, "WDGT", 1000, outcome: "c_or_better")
    take(past_term, "WDGT", 1100, outcome: "passed_below_c")

    expect(statuses(progress).map(&:last)).to eq(%w[done done])
  end

  it "meets a choice with any option, and an elective slot with a course from its list" do
    group = create(:elective_group, requirement_set: set, name: "Widget Electives")
    create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3000)
    item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 2000 },
                             { "subject_code" => "WDGT", "course_number" => 2100 } ])
    item(:placeholder, label: "Widget Elective", elective_group: group)
    item(:placeholder, label: "Free Elective")
    take(past_term, "WDGT", 2100)
    take(past_term, "WDGT", 3000)

    rows = progress[:programs].first[:requirements]

    expect(rows.map { |row| row.slice(:kind, :status, :course, :checkable) }).to eq([
      { kind: "choice", status: "done", course: "WDGT 2100", checkable: true },
      { kind: "placeholder", status: "done", course: "WDGT 3000", checkable: true },
      { kind: "placeholder", status: "open", course: nil, checkable: false }
    ])
    expect(rows.first[:options]).to eq([ "WDGT 2000", "WDGT 2100" ])
  end

  it "counts each course once, and gives it to a required row before an elective slot" do
    group = create(:elective_group, requirement_set: set)
    create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 1000)
    item(:placeholder, label: "Widget Elective", elective_group: group)
    item(subject_code: "WDGT", course_number: 1000)
    take(past_term, "WDGT", 1000)

    expect(statuses(progress)).to eq([ [ "Widget Elective", "open" ], [ "WDGT 1000", "done" ] ])
  end

  it "meets an old course code with the new code, through a course code alias" do
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 128, to_subject_code: "WDGT", to_course_number: 1000)
    item(subject_code: "WDGT", course_number: 128)
    take(past_term, "WDGT", 1000)

    expect(progress[:programs].first[:requirements].first).to include(status: "done", course: "WDGT 1000")
  end

  it "checks the elective lists of a program with no plan, such as a minor" do
    minor = create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor")
    minor_set = create(:requirement_set, degree_program: minor, catalog_year: catalog_year, name: "Gear Minor")
    required = create(:elective_group, requirement_set: minor_set, name: "Required Courses", min_courses: nil)
    create(:elective_group_course, elective_group: required, subject_code: "GEAR", course_number: 1000)
    create(:elective_group_course, elective_group: required, subject_code: "GEAR", course_number: 1100)
    credits = create(:elective_group, requirement_set: minor_set, name: "Gear Electives", min_courses: nil, min_credits: 8)
    create(:elective_group_course, elective_group: credits, subject_code: "GEAR", course_number: 2000)
    create(:elective_group_course, elective_group: credits, subject_code: "GEAR", course_number: 2100)
    take(past_term, "GEAR", 1000)
    take(current_term, "GEAR", 1100)
    take(past_term, "GEAR", 2000)

    rows = progress(program: "gear-minor")[:programs].first[:requirements]

    expect(rows.map { |row| row.slice(:elective_list, :status, :courses) }).to eq([
      { elective_list: "Required Courses", status: "in_progress", courses: [ "GEAR 1000", "GEAR 1100" ] },
      { elective_list: "Gear Electives", status: "open", courses: [ "GEAR 2000" ] }
    ])
  end

  # A WIT lecture and its lab share the subject and number.
  describe "a lecture and its lab" do
    let(:minor_set) do
      minor = create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor")
      create(:requirement_set, degree_program: minor, catalog_year: catalog_year, name: "Gear Minor")
    end

    def lab(lecture, credits: nil)
      section = create(:course, term: lecture.term, subject: lecture.subject, course_number: lecture.course_number,
                                credit_hours: credits, schedule_type: :laboratory)
      create(:enrollment, user: user, course: section)
      section
    end

    it "counts as one course, with the credits of the lecture" do
      group = create(:elective_group, requirement_set: minor_set, name: "Gear Electives", min_courses: nil, min_credits: 8)
      create(:elective_group_course, elective_group: group, subject_code: "GEAR", course_number: 2000)
      lab(take(past_term, "GEAR", 2000, credits: 4))

      result = progress(program: "gear-minor")

      expect(result[:courses].size).to eq(1)
      expect(result[:courses].first).to include(code: "GEAR 2000", credits: 4)
      expect(result[:programs].first[:requirements].first).to include(status: "open", courses: [ "GEAR 2000" ])
    end

    it "is not passed when the lecture failed and the lab has no outcome" do
      item(subject_code: "GEAR", course_number: 1000)
      lab(take(past_term, "GEAR", 1000, outcome: "failed"))

      expect(statuses(progress)).to eq([ [ "GEAR 1000", "open" ] ])
    end
  end

  it "counts a retake once, with the best attempt" do
    group = create(:elective_group, requirement_set: set, name: "Math Electives", min_courses: 2)
    create(:elective_group_course, elective_group: group, subject_code: "MATH", course_number: 2300)
    create(:elective_group_course, elective_group: group, subject_code: "MATH", course_number: 2400)
    item(:placeholder, label: "Math Elective", elective_group: group)
    item(:placeholder, label: "Math Elective", elective_group: group)
    take(past_term, "MATH", 2300, outcome: "passed_below_c")
    take(current_term, "MATH", 2300)

    rows = progress[:programs].first[:requirements]

    expect(rows.map { |row| [ row[:status], row[:term] ] }).to eq([ [ "done", past_term.name ], [ "open", nil ] ])
  end

  it "does not check a list with no minimum the import could read, unless it is a required list" do
    minor = create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor")
    minor_set = create(:requirement_set, degree_program: minor, catalog_year: catalog_year)
    create(:elective_group_course, subject_code: "GEAR", course_number: 3000,
                                   elective_group: create(:elective_group, requirement_set: minor_set, name: "Gear Electives",
                                                                           min_courses: nil, min_credits: nil))
    take(past_term, "GEAR", 3000)

    expect(progress(program: "gear-minor")[:programs].first[:requirements].first)
      .to include(checkable: false, status: "open", courses: [])
  end

  it "names the minimum grade in its assumptions" do
    expect(described_class::ASSUMPTIONS).to include(a_string_including("C or better"))
  end

  it "checks a program argument in the student's own catalog year, or the one given" do
    set
    newer = create(:catalog_year, :imported, start_year: 2026)
    create(:requirement_set, degree_program: major, catalog_year: newer)

    expect(progress(program: "widget-design-bs")[:programs].first[:catalog_year]).to eq("2025-2026")
    expect(progress(program: "widget-design-bs", catalog_year: "2026-2027")[:programs].first[:catalog_year]).to eq("2026-2027")
    expect { progress(program: "basket-weaving-bs") }.to raise_error(Catalog::FilterError, /list_programs/)
  end

  it "uses the standard plan, or the plan the student names" do
    plan
    create(:program_plan, :accelerated, requirement_set: set)

    expect(progress[:programs].first).to include(plan: "Four Year Program", plans: [ "Four Year Program", "Three Year Program" ])
    expect(progress(plan: "three year program")[:programs].first[:plan]).to eq("Three Year Program")
    expect { progress(plan: "Ten Year Program") }.to raise_error(Catalog::FilterError, /Three Year Program/)
  end

  it "uses the plan the student picked, and the standard plan when an import renamed it" do
    plan
    create(:program_plan, :accelerated, requirement_set: set)

    user.student_programs.sole.update!(plan_name: "Three Year Program")
    expect(progress[:programs].first).to include(plan: "Three Year Program", status: "active")

    user.student_programs.sole.update!(plan_name: "Old Plan")
    expect(progress[:programs].first[:plan]).to eq("Four Year Program")
  end

  it "checks the planned programs too with include_planned, each marked by status" do
    item(subject_code: "WDGT", course_number: 1000)
    minor = create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor")
    minor_set = create(:requirement_set, degree_program: minor, catalog_year: catalog_year, name: "Gear Minor")
    group = create(:elective_group, requirement_set: minor_set, name: "Gear Electives", min_courses: 1)
    create(:elective_group_course, elective_group: group, subject_code: "GEAR", course_number: 2000)
    create(:student_program, :planned, user: user, degree_program: minor, catalog_year: catalog_year)

    expect(progress[:programs].pluck(:program)).to eq([ "widget-design-bs" ])

    programs = progress(include_planned: true)[:programs]
    expect(programs.map { |entry| entry.values_at(:program, :status) })
      .to eq([ [ "widget-design-bs", "active" ], [ "gear-minor", "planned" ] ])
    expect(programs.last[:requirements]).to contain_exactly(include(elective_list: "Gear Electives", status: "open"))
  end

  it "keeps the active entry when an older planned row has the same program" do
    set
    user.student_programs.destroy_all
    create(:student_program, :planned, user: user, degree_program: major, catalog_year: catalog_year)
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)

    expect(progress(include_planned: true)[:programs].pluck(:status)).to eq(%w[planned active])
    expect(progress[:programs].pluck(:status)).to eq(%w[active])
  end

  it "uses the student's picked plan for their own program named as the argument, unless a plan is given" do
    plan
    create(:program_plan, :accelerated, requirement_set: set)
    user.student_programs.sole.update!(plan_name: "Three Year Program")

    expect(progress(program: "widget-design-bs")[:programs].first[:plan]).to eq("Three Year Program")
    expect(progress(program: "widget-design-bs", plan: "Four Year Program")[:programs].first[:plan]).to eq("Four Year Program")
  end

  it "loads the requirements of every program with a fixed number of queries" do
    item(subject_code: "WDGT", course_number: 1000)
    one = progress
    minors = create_list(:degree_program, 3, :minor)
    minors.each do |minor|
      create(:requirement_set, degree_program: minor, catalog_year: catalog_year)
      create(:student_program, :planned, user: user, degree_program: minor, catalog_year: catalog_year)
    end

    expect(Prosopite.scan { progress(include_planned: true) }[:programs].size).to eq(one[:programs].size + 3)
  end

  it "counts a course in an old term with no end date as done when it is before the current term" do
    item(subject_code: "WDGT", course_number: 1000)
    take(create(:term, year: 2019, season: :fall), "WDGT", 1000)
    allow(Term).to receive(:current).and_return(current_term)

    expect(statuses(progress)).to eq([ [ "WDGT 1000", "done" ] ])
  end
end
