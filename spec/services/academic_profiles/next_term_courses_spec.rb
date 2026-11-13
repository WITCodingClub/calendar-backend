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
  let(:past_term) { create(:term, uid: 202610, year: 2025, season: :fall, end_date: Date.new(2025, 12, 20)) }
  let(:current_term) { create(:term, uid: 202710, year: 2026, season: :fall, end_date: Date.new(2026, 12, 20)) }
  # Spring 2027: year 2, spring of a Fall 2025 start.
  let(:spring_uid) { 202720 }

  before do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610)
  end

  def result(term_uid: spring_uid)
    described_class.new(user, term_uid: term_uid, current_term_uid: 202710, today: today).call
  end

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

  it "gives each course its catalog details, and an elective slot its list (#989)" do
    create(:catalog_course, :with_details, subject_code: "WDGT", course_number: 2100, title: "Widget Design",
                                           description: "Designing widgets.", typically_offered: %w[Spring])
    group = create(:elective_group, requirement_set: set, name: "Widget Electives", heading: "Widget elective",
                                    min_courses: 1, notes: nil)
    item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 2100 },
                             { "subject_code" => "WDGT", "course_number" => 2150 } ])
    item(:placeholder, label: "Widget Elective", elective_group: group)

    choice, slot = program[:planned]

    expect(choice[:list]).to be_nil
    expect(choice[:courses].first).to include(code: "WDGT 2100", title: "Widget Design", description: "Designing widgets.",
                                              credit_hours: 4, typically_offered: %w[Spring])
    expect(choice[:courses].second).to include(code: "WDGT 2150", title: nil, description: nil, credit_hours: nil,
                                               typically_offered: nil)
    expect(slot[:list]).to eq(heading: "Widget elective", notes: nil, min_courses: 1, min_credits: nil, subject_codes: [])
  end

  it "loads the catalog courses in one query" do
    create(:catalog_course, :with_details, subject_code: "WDGT", course_number: 2100)
    item(subject_code: "WDGT", course_number: 2100)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?(%("catalog_courses")) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { result }

    expect(queries.size).to eq(1)
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

  it "finds the section of a course whose subject is a Banner label" do
    item(subject_code: "WDGT", course_number: 2100)
    spring = create(:term, uid: spring_uid, year: 2027, season: :spring)
    create(:course, term: spring, subject: "Widget Design (WDGT)", course_number: 2100)

    expect(program[:planned].first[:courses].first[:offered]).to be(true)
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
      [ "WDGT 2200", "not_met", [ "WDGT 1100 or WDGT 1200" ] ],
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

  it "does not count a course in the term or later for a prerequisite, and a minimum above C is unknown" do
    item(subject_code: "WDGT", course_number: 2100)
    item(subject_code: "WDGT", course_number: 2200)
    requires("WDGT", 2100, course_leaf("WDGT", 1500))
    requires("WDGT", 2200, course_leaf("WDGT", 1000, min_grade: "B-"))
    take(create(:term, uid: spring_uid, year: 2027, season: :spring), "WDGT", 1500)
    take(past_term, "WDGT", 1000)

    expect(program[:planned].map { |row| row[:courses].first[:prerequisites] }).to eq(%w[not_met unknown])
  end

  it "keeps an and inside an or as one missing option" do
    item(subject_code: "WDGT", course_number: 2100)
    requires("WDGT", 2100, { "type" => "or", "operands" => [
      course_leaf("WDGT", 1100),
      { "type" => "and", "operands" => [ course_leaf("WDGT", 1200), course_leaf("WDGT", 1300) ] }
    ] })

    expect(program[:planned].first[:courses].first[:missing]).to eq([ "WDGT 1100 or (WDGT 1200 and WDGT 1300)" ])
  end

  it "finds the sections and catalog details of an old plan code through its alias" do
    item(subject_code: "WDGT", course_number: 210)
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 210, to_subject_code: "WDGT", to_course_number: 2100)
    create(:catalog_course, subject_code: "WDGT", course_number: 2100, title: "Widget Studio")
    create(:course, term: create(:term, uid: spring_uid, year: 2027, season: :spring), subject: "WDGT", course_number: 2100)

    expect(program[:planned].first[:courses].first).to include(code: "WDGT 210", title: "Widget Studio", offered: true)
  end

  it "does not list a row as behind before its term starts" do
    item(year: 2, season: "fall", subject_code: "WDGT", course_number: 2000)
    item(year: 2, season: "spring", subject_code: "WDGT", course_number: 2100)
    item(year: 3, season: "fall", subject_code: "WDGT", course_number: 3000)

    future = result(term_uid: 202810)[:programs].first
    expect(future[:planned].pluck(:code)).to eq([ "WDGT 3000" ])
    expect(future[:behind].pluck(:code)).to eq([ "WDGT 2000" ])
  end

  it "lists a program once when two LeopardWeb rows link to it" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, catalog_term_uid: 202610,
                             concentration: "Gears")
    item(subject_code: "WDGT", course_number: 2100)

    expect(result[:programs].size).to eq(1)
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

  describe "assumed courses and missing_in_plan (#996)" do
    let(:fall_uid) { 202810 }

    def result(term_uid: spring_uid, **options)
      described_class.new(user, term_uid: term_uid, current_term_uid: 202710, today: today, **options).call
    end

    def plan_for(uid, *codes)
      term = Term.find_by(uid: uid) || create(:term, uid: uid, year: uid / 100, season: uid % 100 == 10 ? :fall : :spring)
      create(:registration_plan, user: user, term: term, courses: codes.map { |code| { "code" => code, "crns" => [ "20410" ] } })
    end

    def first_course(hash) = hash[:programs].first[:planned].first[:courses].first

    it "leaves out assumed and gives an empty missing_in_plan without the new arguments" do
      item(subject_code: "WDGT", course_number: 2100)
      requires("WDGT", 2100, course_leaf("WDGT", 1000))

      hash = result
      expect(hash).not_to have_key(:assumed)
      expect(first_course(hash)).to include(prerequisites: "not_met", missing: [ "WDGT 1000" ], missing_in_plan: [])
      expect(hash[:assumptions].size).to eq(3)
    end

    it "counts an assumed course as passed with a C or better, and lists it" do
      item(subject_code: "WDGT", course_number: 2100)
      requires("WDGT", 2100, { "type" => "and", "operands" => [ course_leaf("WDGT", 1000, min_grade: "C"),
                                                                course_leaf("WDGT", 1100) ] })

      hash = result(assume: [ [ "WDGT", 1100 ], [ "WDGT", 1000 ] ])

      expect(hash.keys.first(2)).to eq(%i[term assumed])
      expect(hash[:assumed]).to eq(courses: [ "WDGT 1000", "WDGT 1100" ], from_plans: [])
      expect(first_course(hash)).to include(prerequisites: "met", missing: [], missing_in_plan: [])
      expect(hash[:assumptions]).to include(a_string_including("A course in assumed counts toward prerequisites"))
    end

    it "does not list a course the student did or takes, also through an alias" do
      item(subject_code: "WDGT", course_number: 2100)
      create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 105, to_subject_code: "WDGT", to_course_number: 1050)
      take(past_term, "WDGT", 105)
      take(current_term, "WDGT", 1000)

      hash = result(assume: [ [ "WDGT", 1000 ], [ "WDGT", 1050 ] ])

      expect(hash[:assumed]).to eq(courses: [], from_plans: [])
      expect(hash[:assumptions]).not_to include(a_string_including("assumed"))
    end

    it "keeps an assumed retake of a course passed below C, so it meets a minimum grade of C" do
      item(subject_code: "WDGT", course_number: 2100)
      requires("WDGT", 2100, course_leaf("WDGT", 1000, min_grade: "C"))
      take(past_term, "WDGT", 1000, outcome: "passed_below_c")

      hash = result(assume: [ [ "WDGT", 1000 ] ])

      expect(hash[:assumed][:courses]).to eq([ "WDGT 1000" ])
      expect(first_course(hash)[:prerequisites]).to eq("met")
    end

    it "counts no plan without a current term" do
      item(year: 3, season: "fall", subject_code: "WDGT", course_number: 3100)
      plan_for(spring_uid, "WDGT 2350")
      allow(Term).to receive(:current_uid).and_return(nil)

      hash = described_class.new(user, term_uid: fall_uid, assume_plans: true, today: today).call

      expect(hash[:assumed]).to eq(courses: [], from_plans: [])
    end

    it "counts the courses of the saved plans after the current term and before the term" do
      item(year: 3, season: "fall", subject_code: "WDGT", course_number: 3100)
      requires("WDGT", 3100, { "type" => "and", "operands" => [ course_leaf("WDGT", 2350), course_leaf("WDGT", 2450) ] })
      plan_for(current_term.uid, "WDGT 2450")
      plan_for(spring_uid, "wdgt2350", "not a code", "WDGT 2000")
      plan_for(fall_uid, "WDGT 2450")
      take(current_term, "WDGT", 2000)

      hash = result(term_uid: fall_uid, assume_plans: true)

      expect(hash[:assumed]).to eq(courses: [ "WDGT 2350" ], from_plans: [ spring_uid ])
      expect(first_course(hash)).to include(prerequisites: "not_met", missing: [ "WDGT 2450" ])
    end

    it "reads the plans only with assume_plans" do
      item(year: 3, season: "fall", subject_code: "WDGT", course_number: 3100)
      requires("WDGT", 3100, course_leaf("WDGT", 2350))
      plan_for(spring_uid, "WDGT 2350")

      expect(first_course(result(term_uid: fall_uid))[:prerequisites]).to eq("not_met")
      expect(first_course(result(term_uid: fall_uid, assume_plans: true))[:prerequisites]).to eq("met")
    end

    it "gives an empty assumed with assume_plans and no plan" do
      item(subject_code: "WDGT", course_number: 2100)

      expect(result(assume_plans: true)[:assumed]).to eq(courses: [], from_plans: [])
    end

    it "lists in missing_in_plan the missing courses that a planned or behind row names" do
      item(year: 1, season: "spring", subject_code: "WDGT", course_number: 1100)
      item(subject_code: "WDGT", course_number: 2100)
      item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 1280 },
                               { "subject_code" => "WDGT", "course_number" => 1290 } ])
      item(subject_code: "WDGT", course_number: 2200)
      requires("WDGT", 2100, { "type" => "and", "operands" => [
        course_leaf("WDGT", 1100), course_leaf("WDGT", 1280), course_leaf("WDGT", 1500)
      ] })
      requires("WDGT", 2200, { "type" => "or", "operands" => [ course_leaf("WDGT", 1290), course_leaf("WDGT", 1300) ] })

      courses = program[:planned].flat_map { |row| row[:courses] }.index_by { |course| course[:code] }
      expect(courses["WDGT 2100"]).to include(missing: [ "WDGT 1100", "WDGT 1280", "WDGT 1500" ],
                                              missing_in_plan: [ "WDGT 1100", "WDGT 1280" ])
      expect(courses["WDGT 2200"]).to include(missing: [ "WDGT 1290 or WDGT 1300" ], missing_in_plan: [ "WDGT 1290" ])
    end

    it "finds a missing course in a row through an alias" do
      item(subject_code: "WDGT", course_number: 2100)
      item(subject_code: "WDGT", course_number: 128)
      create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 128, to_subject_code: "WDGT", to_course_number: 1280)
      requires("WDGT", 2100, course_leaf("WDGT", 1280))

      expect(program[:planned].first[:courses].first[:missing_in_plan]).to eq([ "WDGT 1280" ])
    end
  end

  describe "candidates (#993)" do
    let(:spring) { create(:term, uid: spring_uid, year: 2027, season: :spring) }

    def with_candidates(term_uid: spring_uid)
      described_class.new(user, term_uid: term_uid, current_term_uid: 202710, include_candidates: true, today: today).call
    end

    def offer(subject, number, seats: nil, **attributes)
      create(:course, term: spring, subject: subject, course_number: number, seats_available: seats,
                      seats_capacity: seats && 30, **attributes)
    end

    def codes(row) = row[:candidates].pluck(:code)

    it "adds hss_category to each row, and no candidates or new assumption without include" do
      offer("WDGT", 2100)
      item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 2100 }, { "subject_code" => "WDGT", "course_number" => 2150 } ])

      result = described_class.new(user, term_uid: spring_uid, current_term_uid: 202710, today: today).call
      row = result[:programs].first[:planned].first

      expect(row).to include(hss_category: nil)
      expect(row).not_to have_key(:candidates)
      expect(result[:assumptions].join).not_to include("Candidates")
      expect(with_candidates[:assumptions].last).to start_with("Candidates are recommendations, not a registration check.")
    end

    it "lists the offered options of a choice, with an active section only, and not the course of a course row" do
      offer("Widget Design (WDGT)", 2100)
      offer("WDGT", 2150)
      offer("WDGT", 2175, status: "cancelled")
      item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 2100 }, { "subject_code" => "WDGT", "course_number" => 2150 },
                               { "subject_code" => "WDGT", "course_number" => 2175 }, { "subject_code" => "WDGT", "course_number" => 2199 } ])
      item(subject_code: "WDGT", course_number: 2100)

      course_row, choice = with_candidates[:programs].first[:planned].partition { |row| row[:kind] == "course" }.map(&:first)

      # The course row takes WDGT 2100, so the choice does not list it.
      expect(codes(choice)).to eq([ "WDGT 2150" ])
      expect(course_row).not_to have_key(:candidates)
    end

    it "takes the courses and subjects of the elective list, with the catalog details, prerequisites, and seats" do
      group = create(:elective_group, requirement_set: set, name: "Widget Electives", subject_codes: %w[GIZM])
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3100)
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3200)
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3300)
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3400)
      # WDGT 3400 fills the first slot, so the second slot does not list it.
      2.times { item(:placeholder, label: "Widget Elective", elective_group: group) }
      create(:catalog_course, subject_code: "WDGT", course_number: 3100, title: "Widget Theory", credit_hours: 4,
                              prerequisites: course_leaf("WDGT", 1000))
      requires("WDGT", 3200, course_leaf("WDGT", 2000))
      take(past_term, "WDGT", 1000)
      take(past_term, "WDGT", 3400)
      offer("WDGT", 3100, seats: 0)
      offer("WDGT", 3100, seats: 5)
      offer("WDGT", 3200, seats: 3)
      offer("WDGT", 3300, title: "Widget Lab", credit_hours: 3)
      offer("WDGT", 3400)
      offer("GIZM", 1000, seats: 0)
      offer("OTHR", 1000)

      slot = with_candidates[:programs].first[:planned].first

      expect(slot[:candidates]).to match([
        { code: "WDGT 3100", title: "Widget Theory", credits: 4, hss_category: nil, prerequisites: "met", missing: [],
          missing_in_plan: [], open_seats: true },
        { code: "WDGT 3300", title: "Widget Lab", credits: 3, hss_category: nil, prerequisites: nil, missing: [],
          missing_in_plan: [], open_seats: nil },
        { code: "GIZM 1000", title: anything, credits: nil, hss_category: nil, prerequisites: nil, missing: [],
          missing_in_plan: [], open_seats: false },
        { code: "WDGT 3200", title: anything, credits: anything, hss_category: nil, prerequisites: "not_met",
          missing: [ "WDGT 2000" ], missing_in_plan: [], open_seats: true }
      ])
    end

    it "uses a checked alias to find a course of the list and to leave out a course the student took" do
      group = create(:elective_group, requirement_set: set, name: "Widget Electives")
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 310)
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3200)
      create(:course_code_alias, :reviewed, from_subject_code: "WDGT", from_course_number: 310, to_subject_code: "WDGT", to_course_number: 3100)
      create(:course_code_alias, :reviewed, from_subject_code: "WDGT", from_course_number: 320, to_subject_code: "WDGT", to_course_number: 3200)
      2.times { item(:placeholder, label: "Widget Elective", elective_group: group) }
      take(past_term, "WDGT", 320)
      offer("WDGT", 3100)
      offer("WDGT", 3200)

      expect(codes(with_candidates[:programs].first[:planned].first)).to eq([ "WDGT 3100" ])
    end

    it "lists only the courses of the HSS category that the slot still needs, each with its category" do
      set.update!(hss_requirement: { "min_credits" => 20, "categories" => DegreeRequirements::HssNoteParser.base_categories + [
        { "name" => "Ethics", "subject_codes" => [], "courses" => %w[PHIL4501] }
      ] })
      hss = create(:elective_group, :subjects, requirement_set: set, subject_codes: DegreeRequirements::SharedElectives::HSS.subject_codes)
      item(:placeholder, year: 1, season: "fall", label: "HSS Elective", elective_group: hss)
      item(:placeholder, year: 1, season: "fall", label: "HSS Elective", elective_group: hss)
      item(:placeholder, label: "HSS Elective", elective_group: hss)
      take(past_term, "HIST", 1000)
      take(past_term, "PSYC", 1000)
      offer("PHIL", 4501)
      offer("PSYC", 1500)
      offer("HIST", 2000)

      slot = with_candidates[:programs].first[:planned].first

      expect(slot).to include(hss_category: "Ethics")
      expect(slot[:candidates]).to contain_exactly(include(code: "PHIL 4501", hss_category: "Ethics"))
    end

    it "gives an HSS slot with every category met the HSS courses, each with its category" do
      hss = create(:elective_group, :subjects, requirement_set: set, subject_codes: %w[HIST PSYC])
      3.times { item(:placeholder, label: "HSS Elective", elective_group: hss) }
      take(past_term, "HIST", 1000)
      take(past_term, "PSYC", 1000)
      offer("PSYC", 1500)
      offer("HIST", 2000)
      offer("WDGT", 2000)

      slot = with_candidates[:programs].first[:planned].first

      expect(slot[:candidates].pluck(:code, :hss_category)).to eq([ [ "HIST 2000", "Humanities" ], [ "PSYC 1500", "Social Sciences" ] ])
    end

    it "reads the term elective lists for a slot with no list, by heading and school" do
      set.update!(school_name: "The School of Computing and Data Science")
      item(:placeholder, label: "COMP Cryptography Elective 1")
      item(:placeholder, label: "Domain Elective")
      scds = create(:term_elective_list, term: spring, school: "SCDS")
      soe = create(:term_elective_list, term: spring, school: "SOE")
      create(:term_elective_course, term_elective_list: scds, subject_code: "COMP", course_number: 4500, heading: "Cryptography Elective")
      create(:term_elective_course, term_elective_list: scds, subject_code: "COMP", course_number: 4600, heading: "Computer Science Elective")
      create(:term_elective_course, term_elective_list: soe, subject_code: "MECH", course_number: 4500, heading: "Domain Electives")
      offer("COMP", 4500)
      offer("COMP", 4600)
      offer("MECH", 4500)

      crypto, domain = with_candidates[:programs].first[:planned]

      expect(codes(crypto)).to eq([ "COMP 4500" ])
      expect(domain[:candidates]).to eq([])
    end

    it "gives a free elective only the courses of a term list heading that names it, for degree credit" do
      free = create(:elective_group, :any_course, requirement_set: set)
      item(:placeholder, label: "Free Elective", elective_group: free)
      offer("WDGT", 2000)

      expect(with_candidates[:programs].first[:planned].first[:candidates]).to eq([])

      list = create(:term_elective_list, term: spring, school: "HSS")
      create(:term_elective_course, term_elective_list: list, subject_code: "WDGT", course_number: 2000, heading: "Free Electives")
      create(:term_elective_course, term_elective_list: list, subject_code: "ENGL", course_number: 700, heading: "Free Electives")
      offer("ENGL", 700)

      expect(codes(with_candidates[:programs].first[:planned].first)).to eq([ "WDGT 2000" ])
    end

    it "leaves out an assumed course and a course that a course row of the term names" do
      group = create(:elective_group, requirement_set: set, name: "Widget Electives", subject_codes: %w[WDGT])
      item(:placeholder, label: "Widget Elective", elective_group: group)
      item(subject_code: "WDGT", course_number: 3200)
      [ 3100, 3200, 3300 ].each { |number| offer("WDGT", number) }

      result = described_class.new(user, term_uid: spring_uid, current_term_uid: 202710, assume: [ [ "WDGT", 3100 ] ],
                                          include_candidates: true, today: today).call
      slot = result[:programs].first[:planned].find { |row| row[:kind] == "placeholder" }

      expect(codes(slot)).to eq([ "WDGT 3300" ])
    end

    it "sorts candidates by subject and number, and reads a term list with no school" do
      set.update!(school_name: "The School of Computing and Data Science")
      item(:placeholder, label: "Cryptography Elective")
      list = create(:term_elective_list, term: spring, school: nil)
      [ 1000, 700 ].each do |number|
        create(:term_elective_course, term_elective_list: list, subject_code: "ENGL", course_number: number, heading: "Cryptography Electives")
        offer("ENGL", number)
      end

      expect(codes(with_candidates[:programs].first[:planned].first)).to eq([ "ENGL 700", "ENGL 1000" ])
    end

    it "has no candidates when WIT Calendar has no sections of the term yet" do
      item(:choice, options: [ { "subject_code" => "WDGT", "course_number" => 2100 }, { "subject_code" => "WDGT", "course_number" => 2150 } ])

      result = with_candidates

      expect(result[:sections]).to be(false)
      expect(result[:programs].first[:planned].first[:candidates]).to eq([])
    end

    it "keeps the first candidates up to the limit" do
      stub_const("AcademicProfiles::ElectiveCandidates::LIMIT", 2)
      item(:choice, options: [ 2100, 2200, 2300 ].map { |number| { "subject_code" => "WDGT", "course_number" => number } })
      [ 2300, 2200, 2100 ].each { |number| offer("WDGT", number) }

      expect(codes(with_candidates[:programs].first[:planned].first)).to eq([ "WDGT 2100", "WDGT 2200" ])
    end

    it "gives behind rows candidates too" do
      item(:choice, year: 1, season: "fall", options: [ { "subject_code" => "WDGT", "course_number" => 1000 },
                                                        { "subject_code" => "WDGT", "course_number" => 1050 } ])
      offer("WDGT", 1000)

      expect(codes(with_candidates[:programs].first[:behind].first)).to eq([ "WDGT 1000" ])
    end

    it "runs the same number of queries for one row and for several rows" do
      group = create(:elective_group, requirement_set: set, name: "Widget Electives", subject_codes: %w[GIZM])
      create(:elective_group_course, elective_group: group, subject_code: "WDGT", course_number: 3100)
      create(:term_elective_list, term: spring, school: "SCDS").then do |list|
        create(:term_elective_course, term_elective_list: list, subject_code: "COMP", course_number: 4500, heading: "Cryptography Elective")
      end
      item(:placeholder, label: "Cryptography Elective")
      item(:placeholder, label: "Widget Elective", elective_group: group)
      item(:choice, options: [ { "subject_code" => "COMP", "course_number" => 4500 }, { "subject_code" => "COMP", "course_number" => 4510 } ])
      requires("WDGT", 3100, course_leaf("WDGT", 1000))
      offer("WDGT", 3100, seats: 2)
      offer("GIZM", 1000)
      offer("COMP", 4500)

      count = lambda do
        queries = 0
        callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { with_candidates }
        queries
      end
      count.call # warms the caches of the first request
      one = count.call

      item(:placeholder, label: "Cryptography Elective")
      item(:placeholder, label: "Widget Elective", elective_group: group)
      item(:placeholder, label: "Widget Elective", elective_group: group)
      item(:choice, options: [ { "subject_code" => "GIZM", "course_number" => 1000 }, { "subject_code" => "COMP", "course_number" => 4510 } ])

      expect(with_candidates[:programs].first[:planned].count { |row| row[:candidates].any? }).to eq(7)
      expect(count.call).to eq(one)
    end
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
