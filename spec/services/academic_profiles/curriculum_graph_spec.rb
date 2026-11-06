# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::CurriculumGraph do
  let(:user) { create(:user) }
  let(:today) { Date.new(2026, 11, 6) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }
  let(:set) { create(:requirement_set, degree_program: major, catalog_year: catalog_year, name: "Widget Design, B.S.") }
  let(:plan) { create(:program_plan, requirement_set: set) }
  let(:past_term) { create(:term, year: 2025, season: :fall, end_date: Date.new(2025, 12, 20)) }
  let(:current_term) { create(:term, year: 2026, season: :fall, end_date: Date.new(2026, 12, 20)) }

  let(:intro) { create(:catalog_course, subject_code: "WDGT", course_number: 1000, title: "Intro to Widgets") }
  let(:advanced) { create(:catalog_course, subject_code: "WDGT", course_number: 2000, title: "Advanced Widgets") }
  let(:capstone) { create(:catalog_course, subject_code: "WDGT", course_number: 3000, title: "Widget Capstone") }

  def graph(**arguments) = described_class.new(user, today: today, **arguments).call

  def item(year, season, kind = nil, **attributes)
    create(:program_plan_item, *[ kind ].compact, program_plan: plan, year_index: year, season: season, **attributes)
  end

  def take(term, subject, number)
    create(:enrollment, user: user, course: create(:course, term: term, subject: subject, course_number: number))
  end

  before do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)
    create(:course_prerequisite, catalog_course: advanced, required_catalog_course: intro)
    create(:course_prerequisite, catalog_course: capstone, required_catalog_course: advanced)
    item(1, "fall", subject_code: "WDGT", course_number: 1000, label: "Intro to Widgets")
    item(1, "spring", subject_code: "WDGT", course_number: 2000, label: "Advanced Widgets")
    item(1, "spring", :placeholder, label: "Free Elective")
    item(2, "fall", subject_code: "WDGT", course_number: 3000, label: "Widget Capstone")
  end

  it "groups the plan rows by semester, with the status of each row" do
    take(past_term, "WDGT", 1000)
    take(current_term, "WDGT", 2000)

    result = graph

    expect(result).to include(program: "widget-design-bs", name: "Widget Design, B.S.", catalog_year: "2025-2026",
                              programs: [ { program: "widget-design-bs", name: "Widget Design, B.S.", catalog_year: "2025-2026", role: "major" } ])
    expect(result[:semesters].map { |semester| [ semester[:label], semester[:nodes].map { |node| [ node[:code] || node[:label], node[:status] ] } ] })
      .to eq([ [ "Year 1 Fall", [ [ "WDGT 1000", "done" ] ] ],
               [ "Year 1 Spring", [ [ "WDGT 2000", "in_progress" ], [ "Free Elective", "open" ] ] ],
               [ "Year 2 Fall", [ [ "WDGT 3000", "open" ] ] ] ])
    expect(result[:next_semester]).to eq(year: 2, season: "fall", label: "Year 2 Fall")
  end

  it "makes the first semester with an open course next, but not one with only a free elective open" do
    take(past_term, "WDGT", 1000)

    expect(graph[:next_semester]).to include(label: "Year 1 Spring")

    take(current_term, "WDGT", 2000)

    expect(graph[:next_semester]).to include(label: "Year 2 Fall")
  end

  it "draws an edge from each prerequisite to the plan course that needs it" do
    edges = graph[:edges]

    expect(edges).to contain_exactly({ from: "n1", to: "n2" }, { from: "n2", to: "n4" })
  end

  it "links a choice by its options, so a prerequisite of an option draws an edge" do
    plan.items.find_by(course_number: 2000).destroy!
    item(1, "spring", :choice, options: [ { "subject_code" => "WDGT", "course_number" => 2000 },
                                          { "subject_code" => "WDGT", "course_number" => 2100 } ])

    result = graph
    choice = result[:semesters].flat_map { |semester| semester[:nodes] }.find { |node| node[:kind] == "choice" }

    expect(result[:edges]).to include({ from: "n1", to: choice[:id] }, { from: choice[:id], to: "n3" })
  end

  it "has no next semester when every row is done or in progress" do
    plan.items.where(kind: "placeholder").destroy_all
    [ 1000, 2000, 3000 ].each { |number| take(past_term, "WDGT", number) }

    expect(graph[:next_semester]).to be_nil
  end

  it "shows what comes before and after a focus course, with the student's status" do
    take(past_term, "WDGT", 1000)

    focus = graph(focus: "WDGT2000")[:focus]

    expect(focus).to include(code: "WDGT 2000", title: "Advanced Widgets", status: "open",
                             before: [ { code: "WDGT 1000", title: "Intro to Widgets", status: "done" } ],
                             after: [ { code: "WDGT 3000", title: "Widget Capstone", status: "open" } ])
  end

  it "focuses a course outside the plan" do
    other = create(:catalog_course, subject_code: "WDGT", course_number: 4000, title: "Widget Research")
    create(:course_prerequisite, catalog_course: other, required_catalog_course: capstone)

    expect(graph(focus: "WDGT 3000")[:focus][:after]).to eq([ { code: "WDGT 4000", title: "Widget Research", status: "open" } ])
  end

  it "raises a filter error for an unknown focus course" do
    expect { graph(focus: "ZZZZ 9999") }.to raise_error(Catalog::FilterError, /No course ZZZZ 9999/)
  end

  it "has no semesters for a program with no plan of study" do
    plan.destroy!

    expect(graph[:semesters]).to eq([])
  end

  it "raises NoProgramError when the student has no linked program" do
    user.student_programs.update_all(degree_program_id: nil) # rubocop:disable Rails/SkipsModelValidations

    expect { graph }.to raise_error(AcademicProfiles::DegreeProgress::NoProgramError)
  end

  it "shows the major with a plan, not a minor saved before it" do
    minor = create(:degree_program, slug: "gadget-minor", name: "Gadget Minor")
    create(:requirement_set, degree_program: minor, catalog_year: catalog_year, name: "Gadget Minor")
    user.student_programs.destroy_all
    create(:student_program, :minor, user: user, degree_program: minor, catalog_year: catalog_year)
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year)

    result = graph

    expect(result[:program]).to eq("widget-design-bs")
    expect(result[:programs].pluck(:program)).to eq([ "widget-design-bs", "gadget-minor" ])
    expect(graph(program: "gadget-minor")[:semesters]).to eq([])
  end

  it "puts the next semester after the last one the student started, and lists earlier open rows as behind" do
    take(current_term, "WDGT", 2000)

    result = graph

    expect(result[:next_semester]).to include(label: "Year 2 Fall")
    expect(result[:behind]).to eq([ { id: "n1", kind: "course", code: "WDGT 1000", label: "Intro to Widgets", options: [],
                                      semester: "Year 1 Fall" } ])
  end

  it "gives a focus course the status of a course the student took under an old code" do
    create(:course_code_alias, from_subject_code: "WDGT", from_course_number: 100, to_subject_code: "WDGT", to_course_number: 1000)
    take(past_term, "WDGT", 100)

    focus = graph(focus: "WDGT 2000")[:focus]

    expect(focus[:before]).to eq([ { code: "WDGT 1000", title: "Intro to Widgets", status: "done" } ])
  end

  it "draws an edge from every node that stands for a prerequisite" do
    item(1, "spring", :choice, options: [ { "subject_code" => "WDGT", "course_number" => 1000 },
                                          { "subject_code" => "WDGT", "course_number" => 1100 } ])

    expect(graph[:edges]).to include({ from: "n1", to: "n2" }, { from: "n5", to: "n2" })
  end
end
