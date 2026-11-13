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

  it "meets a subject list with a course in a subject, and a free elective with any course left" do
    free = create(:elective_group, :any_course, requirement_set: set)
    science = create(:elective_group, :subjects, requirement_set: set, name: "Science Electives", subject_codes: %w[BIOL CHEM])
    item(:placeholder, label: "Free Elective", elective_group: free)
    item(:placeholder, label: "Science Elective", elective_group: science)
    item(:placeholder, label: "Science Elective", elective_group: science)
    take(past_term, "CHEM", 1000)
    take(current_term, "WDGT", 2000)

    rows = progress[:programs].first[:requirements]

    # The free elective is first in the plan, but takes a course only after
    # the subject slots, so it does not use the CHEM course.
    expect(rows.map { |row| row.slice(:label, :status, :course, :checkable) }).to eq([
      { label: "Free Elective", status: "in_progress", course: "WDGT 2000", checkable: true },
      { label: "Science Elective", status: "done", course: "CHEM 1000", checkable: true },
      { label: "Science Elective", status: "open", course: nil, checkable: true }
    ])
    expect(progress[:programs].first[:hss]).to be_nil
  end

  describe "the HSS requirement of the major" do
    let(:hss) { create(:elective_group, :subjects, requirement_set: set, subject_codes: DegreeRequirements::SharedElectives::HSS.subject_codes) }

    def hss_rows(result) = result[:programs].first[:requirements].map { |row| row.slice(:status, :course, :hss_category) }

    before { 3.times { item(:placeholder, label: "HSS Elective", elective_group: hss) } }

    it "gives the first HSS slots to one humanities and one social science course, then any HSS course" do
      take(past_term, "PSYC", 1000)
      take(past_term, "PSYC", 2000)
      take(past_term, "HIST", 1000)

      expect(hss_rows(progress)).to eq([
        { status: "done", course: "HIST 1000", hss_category: "Humanities" },
        { status: "done", course: "PSYC 1000", hss_category: "Social Sciences" },
        { status: "done", course: "PSYC 2000", hss_category: nil }
      ])
    end

    it "keeps a slot open for a category no course meets, and reports the categories and credits" do
      set.update!(hss_requirement: { "min_credits" => 20, "categories" => DegreeRequirements::HssNoteParser.base_categories + [
        { "name" => "Ethics", "subject_codes" => [], "courses" => %w[PHIL4501] },
        { "name" => "Design History", "subject_codes" => [], "courses" => [] }
      ] })
      english = create(:elective_group, requirement_set: set, name: "English Sequence")
      create(:elective_group_course, elective_group: english, subject_code: "ENGL", course_number: 1100)
      item(:placeholder, label: "English Sequence", elective_group: english)
      take(past_term, "ENGL", 1100)
      take(past_term, "HIST", 1000)
      take(past_term, "PSYC", 1000)
      take(past_term, "PSYC", 2000)

      result = progress

      expect(hss_rows(result).first(3)).to eq([
        { status: "done", course: "HIST 1000", hss_category: "Humanities" },
        { status: "done", course: "PSYC 1000", hss_category: "Social Sciences" },
        { status: "open", course: nil, hss_category: "Ethics" }
      ])
      expect(result[:programs].first[:hss]).to eq(
        min_credits: 20, credits: 12,
        categories: [
          { name: "Humanities", checkable: true, status: "done", course: "HIST 1000" },
          { name: "Social Sciences", checkable: true, status: "done", course: "PSYC 1000" },
          { name: "Ethics", checkable: true, status: "open", course: nil },
          { name: "Design History", checkable: false, status: "open", course: nil }
        ]
      )
    end

    it "counts a required course row in a category, and its credits" do
      set.update!(hss_requirement: { "min_credits" => 24, "categories" => DegreeRequirements::HssNoteParser.base_categories + [
        { "name" => "Directed: ECON4102", "subject_codes" => [], "courses" => %w[ECON4102] }
      ] })
      item(subject_code: "ECON", course_number: 4102)
      take(past_term, "ECON", 4102)
      take(past_term, "HIST", 1000)
      take(past_term, "LITR", 2000)

      result = progress

      # ECON4102 meets Social Sciences and the directed course, so only
      # Humanities needs a slot.
      expect(hss_rows(result).first(3)).to eq([
        { status: "done", course: "HIST 1000", hss_category: "Humanities" },
        { status: "done", course: "LITR 2000", hss_category: nil },
        { status: "open", course: nil, hss_category: nil }
      ])
      expect(result[:programs].first[:hss]).to include(min_credits: 24, credits: 12)
      expect(result[:programs].first[:hss][:categories].pluck(:status)).to eq(%w[done done done])
    end

    it "counts a third English course as the humanities course" do
      english = create(:elective_group, requirement_set: set, name: "English Sequence")
      [ 900, 1100, 2200 ].each_with_index do |number, index|
        create(:elective_group_course, elective_group: english, subject_code: "ENGL", course_number: number, position: index)
      end
      2.times { item(:placeholder, label: "English Sequence", elective_group: english) }
      [ 900, 1100, 2200 ].each { |number| take(past_term, "ENGL", number) }
      take(past_term, "PSYC", 1000)

      result = progress

      # No slot waits for Humanities: the third English course meets it.
      expect(hss_rows(result).first(3).pluck(:hss_category)).to eq([ "Social Sciences", nil, nil ])
      expect(result[:programs].first[:hss][:categories].first).to include(name: "Humanities", status: "done")
    end

    it "reports the HSS requirement of a plan with no HSS slot" do
      plan.items.delete_all
      set.update!(hss_requirement: DegreeRequirements::HssNoteParser.default)
      item(subject_code: "HIST", course_number: 1000)
      take(past_term, "HIST", 1000)

      expect(progress[:programs].first[:hss][:categories].pluck(:name, :status))
        .to eq([ [ "Humanities", "done" ], [ "Social Sciences", "open" ] ])
    end

    it "counts a course in a Humanities slot toward the humanities category" do
      humanities = create(:elective_group, :subjects, requirement_set: set, name: "Humanities Electives", subject_codes: %w[HIST])
      item(:placeholder, label: "Humanities Elective", elective_group: humanities)
      take(past_term, "HIST", 1000)
      take(past_term, "PSYC", 1000)

      expect(hss_rows(progress)).to eq([
        { status: "done", course: "PSYC 1000", hss_category: "Social Sciences" },
        { status: "open", course: nil, hss_category: nil },
        { status: "open", course: nil, hss_category: nil },
        { status: "done", course: "HIST 1000", hss_category: nil }
      ])
    end
  end

  it "does not meet a free elective with a co-op or a course below 1000" do
    free = create(:elective_group, :any_course, requirement_set: set)
    item(:placeholder, label: "Free Elective", elective_group: free)
    take(past_term, "COOP", 3000)
    take(past_term, "ENGL", 700)

    expect(statuses(progress)).to eq([ [ "Free Elective", "open" ] ])
  end

  it "gives a course to the shorter subject list first" do
    hss = create(:elective_group, :subjects, requirement_set: set, subject_codes: %w[HIST PSYC])
    humanities = create(:elective_group, :subjects, requirement_set: set, name: "Humanities Electives", subject_codes: %w[HIST])
    item(:placeholder, label: "HSS Elective", elective_group: hss)
    item(:placeholder, label: "Humanities Elective", elective_group: humanities)
    take(past_term, "HIST", 1000)
    take(current_term, "PSYC", 1000)

    expect(statuses(progress)).to eq([ [ "HSS Elective", "in_progress" ], [ "Humanities Elective", "done" ] ])
  end

  it "gives a course to a slot with a list of courses before a subject list" do
    hss = create(:elective_group, :subjects, requirement_set: set, subject_codes: %w[PSYC])
    directed = create(:elective_group, requirement_set: set, name: "HSS Elective (PSYC4552)")
    create(:elective_group_course, elective_group: directed, subject_code: "PSYC", course_number: 4552)
    item(:placeholder, label: "HSS Elective", elective_group: hss)
    item(:placeholder, label: "HSS Elective (PSYC4552)", elective_group: directed)
    take(past_term, "PSYC", 4552)

    expect(statuses(progress)).to eq([ [ "HSS Elective", "open" ], [ "HSS Elective (PSYC4552)", "done" ] ])
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
    create(:course_code_alias, :reviewed, from_subject_code: "WDGT", from_course_number: 128, to_subject_code: "WDGT", to_course_number: 1000)
    item(subject_code: "WDGT", course_number: 128)
    take(past_term, "WDGT", 1000)

    expect(progress[:programs].first[:requirements].first).to include(status: "done", course: "WDGT 1000")
  end

  it "does not use an alias that no person has checked" do
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 128, to_subject_code: "WDGT", to_course_number: 1000)
    item(subject_code: "WDGT", course_number: 128)
    take(past_term, "WDGT", 1000)

    expect(progress[:programs].first[:requirements].first).to include(status: "open")
  end

  it "says when a plan from a PDF waits for a check" do
    set.update!(source: "pdf", needs_review: true)
    item(subject_code: "WDGT", course_number: 1000)

    expect(progress[:programs].first[:needs_review]).to be(true)
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

  describe "course details and program totals (#989)" do
    it "gives each course row the details of its course, also through an alias" do
      create(:catalog_course, :with_details, subject_code: "WDGT", course_number: 1000, title: "Widget Basics",
                                             description: "Making widgets.", typically_offered: %w[Fall])
      create(:catalog_course, :with_details, subject_code: "WDGT", course_number: 2000, title: "Widget Design")
      create(:course_code_alias, :reviewed, from_subject_code: "WDGT", from_course_number: 200, to_subject_code: "WDGT", to_course_number: 2000)
      item(subject_code: "WDGT", course_number: 1000)
      item(subject_code: "WDGT", course_number: 200)
      item(subject_code: "WDGT", course_number: 9999)

      rows = progress[:programs].first[:requirements]

      expect(rows.first).to include(title: "Widget Basics", description: "Making widgets.", credit_hours: 4,
                                    typically_offered: %w[Fall], list: nil)
      expect(rows.second).to include(code: "WDGT 200", title: "Widget Design")
      expect(rows.third).to include(title: nil, description: nil, credit_hours: nil, typically_offered: nil)
      expect(rows.first).not_to have_key(:filled_course)
    end

    it "gives a slot its list and the course that fills it, and a choice no list" do
      create(:catalog_course, :with_details, subject_code: "HUMN", course_number: 1500, title: "Intro to Humanities")
      group = create(:elective_group, :subjects, requirement_set: set, name: "Humanities Electives", heading: "Humanities elective",
                                                 notes: "Any humanities course", subject_codes: %w[HUMN PHIL])
      item(:placeholder, label: "Humanities Elective", elective_group: group)
      item(:placeholder, label: "Humanities Elective", elective_group: group)
      item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 2000 },
                               { "subject_code" => "WDGT", "course_number" => 2100 } ])
      take(past_term, "HUMN", 1500)
      take(past_term, "WDGT", 2100)

      filled, open, choice = progress[:programs].first[:requirements]

      expect(filled[:list]).to eq(heading: "Humanities elective", notes: "Any humanities course", min_courses: nil,
                                  min_credits: nil, subject_codes: %w[HUMN PHIL])
      expect(filled[:filled_course]).to include(code: "HUMN 1500", title: "Intro to Humanities", credit_hours: 4)
      expect(open).to include(filled_course: nil, list: filled[:list])
      expect(choice).to include(list: nil)
      # WDGT 2100 has no CatalogCourse row, so it keeps the title of its section.
      expect(choice[:filled_course]).to include(code: "WDGT 2100", title: be_present, description: nil)
      expect(filled).not_to have_key(:title)
    end

    it "sums the credits of the courses taken and counts the co-op semesters" do
      set.update!(total_credits: 132, school_name: "School of Widgets", department_name: "Widget Design")
      co_op = create(:elective_group, requirement_set: set, name: DegreeRequirements::SharedElectives::CO_OP.name)
      create(:elective_group_course, elective_group: co_op, subject_code: "COOP", course_number: 3500)
      item(subject_code: "COOP", course_number: 2500)
      item(:placeholder, label: "Co-op Semester", elective_group: co_op)
      item(:placeholder, label: "Co-op Semester", elective_group: co_op)
      take(past_term, "COOP", 2500, credits: nil)
      take(past_term, "COOP", 3500, credits: nil)
      take(past_term, "WDGT", 1000, credits: 4)
      take(past_term, "WDGT", 1100, credits: 3, outcome: "failed")
      take(current_term, "WDGT", 1100, credits: 3)
      take(current_term, "WDGT", 1200, credits: 4)

      expect(progress[:programs].first[:summary]).to eq(
        total_credits: 132, school: "School of Widgets", department: "Widget Design",
        # The failed WDGT 1100 counts once, with the attempt in progress.
        credits: { earned: 4, in_progress: 7 },
        co_ops: { required: 2, done: 1 }
      )
    end

    it "counts a course row that names a co-op semester" do
      item(subject_code: "COOP", course_number: 3500)
      item(subject_code: "COOP", course_number: 4500)
      take(past_term, "COOP", 3500, credits: nil)

      expect(progress[:programs].first[:summary][:co_ops]).to eq(required: 2, done: 1)
    end

    it "loads the catalog courses of every program in one query" do
      create(:catalog_course, subject_code: "WDGT", course_number: 1000)
      item(subject_code: "WDGT", course_number: 1000)
      minor = create(:degree_program, :minor)
      minor_plan = create(:program_plan, requirement_set: create(:requirement_set, degree_program: minor, catalog_year: catalog_year))
      create(:program_plan_item, program_plan: minor_plan, subject_code: "GEAR", course_number: 1000)
      create(:student_program, :planned, user: user, degree_program: minor, catalog_year: catalog_year)

      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?(%("catalog_courses")) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { progress(include_planned: true) }

      expect(queries.size).to eq(1)
    end
  end

  it "counts a course in an old term with no end date as done when it is before the current term" do
    item(subject_code: "WDGT", course_number: 1000)
    take(create(:term, year: 2019, season: :fall), "WDGT", 1000)
    allow(Term).to receive(:current).and_return(current_term)

    expect(statuses(progress)).to eq([ [ "WDGT 1000", "done" ] ])
  end

  describe "the plan against real terms (#990)" do
    before { allow(Term).to receive(:current).and_return(build_stubbed(:term, uid: 202710, year: 2026, season: :fall)) }

    it "gives the start term of GET /api/user/programs, the timeline, and the planned term of each row" do
      item(subject_code: "WDGT", course_number: 1000)
      item(subject_code: "WDGT", course_number: 2000, year_index: 2, season: "fall")
      item(subject_code: "WDGT", course_number: 3000, year_index: 3, season: "spring")

      program = progress[:programs].sole

      expect(program[:start_term]).to eq(StudentProgramsSerializer.new(user).as_json[:programs].sole[:start_term])
      expect(program[:timeline].map { |semester| semester.values_at(:term, :when, :estimated) })
        .to eq([ [ "Fall 2025", "past", false ], [ "Fall 2026", "current", false ], [ "Spring 2028", "future", true ] ])
      expect(program[:expected_end]).to eq(term: "Spring 2028", estimated: true)
      expect(program[:requirements].map { |row| row.values_at(:code, :planned_term, :planned_term_uid, :behind) })
        .to eq([ [ "WDGT 1000", "Fall 2025", 202610, true ], [ "WDGT 2000", "Fall 2026", 202710, true ],
                 [ "WDGT 3000", "Spring 2028", 202820, false ] ])
    end

    it "takes the start term from the admit term when the program has no catalog term" do
      item(subject_code: "WDGT", course_number: 1000)
      user.student_programs.sole.update!(catalog_term_uid: nil)
      create(:academic_profile, user: user, admit_term_uid: 202620)

      expect(progress[:programs].sole).to include(start_term: "Spring 2026", expected_end: include(term: "Fall 2025"))
    end

    it "has no start term or timeline for a planned program or a program argument" do
      item(subject_code: "WDGT", course_number: 1000)
      user.student_programs.sole.update!(status: "planned", catalog_term_uid: nil)

      [ progress(include_planned: true), progress(program: "widget-design-bs") ].each do |result|
        program = result[:programs].sole
        expect(program).to include(start_term: nil, timeline: [], expected_end: nil)
        expect(program[:requirements].sole).to include(planned_term: nil, planned_term_uid: nil, behind: false)
      end
    end
  end
end
