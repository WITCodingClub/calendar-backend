# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::ProgramTimeline do
  let(:user) { create(:user) }
  let(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs") }
  let(:set) { create(:requirement_set, degree_program: major, catalog_year: catalog_year) }
  let!(:four_year) { create(:program_plan, requirement_set: set) }
  let!(:three_year) { create(:program_plan, :accelerated, requirement_set: set) }

  def timeline(program, admit_term_uid: nil)
    described_class.for_programs([ program ], admit_term_uid: admit_term_uid).fetch(program)
  end

  def program(**attributes)
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, **attributes)
  end

  it "assumes the standard plan until the student picks one" do
    expect(timeline(program)).to have_attributes(plan: four_year, plan_source: "assumed",
                                                 plan_names: [ "Four Year Program", "Three Year Program" ])
  end

  it "uses the plan the student picked" do
    expect(timeline(program(plan_name: "Three Year Program"))).to have_attributes(plan: three_year, plan_source: "student")
  end

  it "falls back to the assumed plan when an import renamed the picked plan" do
    expect(timeline(program(plan_name: "Old Plan"))).to have_attributes(plan: four_year, plan_source: "assumed")
  end

  it "has no plan for a program with no link to the degree catalog" do
    unlinked = create(:student_program, user: user)

    expect(timeline(unlinked)).to have_attributes(plan: nil, plan_source: nil, plan_names: [])
  end

  it "takes the start term from the catalog term, then from the admit term" do
    expect(timeline(program(catalog_term_uid: 202610), admit_term_uid: 202510))
      .to have_attributes(start_term_uid: 202610, start_term_source: "catalog_term")
    expect(timeline(program(catalog_term_uid: nil), admit_term_uid: 202510))
      .to have_attributes(start_term_uid: 202510, start_term_source: "admit_term")
    expect(timeline(program(catalog_term_uid: nil))).to have_attributes(start_term_uid: nil, start_term_source: nil)
  end

  it "gives a planned program no start term" do
    planned = create(:student_program, :planned, user: user, degree_program: major, catalog_year: catalog_year)

    expect(timeline(planned, admit_term_uid: 202510)).to have_attributes(start_term_uid: nil, start_term_source: nil)
  end

  it "maps a plan semester to a real term from the start term" do
    fall_start = timeline(program(catalog_term_uid: 202610)) # Fall 2025

    expect(AcademicProfiles::TermCode.label(fall_start.term_uid(1, "fall"))).to eq("Fall 2025")
    expect(AcademicProfiles::TermCode.label(fall_start.term_uid(3, "fall"))).to eq("Fall 2027")
    expect(AcademicProfiles::TermCode.label(fall_start.term_uid(3, "spring"))).to eq("Spring 2028")
    expect(AcademicProfiles::TermCode.label(fall_start.term_uid(2, "summer"))).to eq("Summer 2027")
    expect(fall_start.term_uid(1, "winter")).to be_nil
  end

  it "puts year 1 in the academic year of a spring start term" do
    spring_start = timeline(program(catalog_term_uid: 202620)) # Spring 2026

    expect(AcademicProfiles::TermCode.label(spring_start.term_uid(1, "fall"))).to eq("Fall 2025")
    expect(AcademicProfiles::TermCode.label(spring_start.term_uid(1, "spring"))).to eq("Spring 2026")
  end

  it "puts year 1 in the academic year after a summer start term" do
    summer_start = timeline(program(catalog_term_uid: 202630)) # Summer 2026

    expect(AcademicProfiles::TermCode.label(summer_start.term_uid(1, "fall"))).to eq("Fall 2026")
    expect(AcademicProfiles::TermCode.label(summer_start.term_uid(3, "fall"))).to eq("Fall 2028")
  end

  it "loads the plans of many programs with a fixed number of queries" do
    programs = [ program, program(catalog_term_uid: 202620) ]
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      described_class.for_programs(programs, admit_term_uid: nil).each_value(&:plan)
    end

    expect(queries).to eq(2)
  end
end
