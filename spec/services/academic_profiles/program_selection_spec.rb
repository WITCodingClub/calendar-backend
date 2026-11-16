# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::ProgramSelection do
  let(:user) { create(:user) }
  let(:catalog_year) { create(:catalog_year, :imported, start_year: 2025) }
  let(:major) { create(:degree_program, slug: "widget-design-bs") }
  let(:set) { create(:requirement_set, degree_program: major, catalog_year: catalog_year) }

  def selection(program: nil, plan: nil, include_planned: false)
    described_class.new(user, program: program, catalog_year: nil, plan: plan, include_planned: include_planned)
  end

  it "gives each active program of the student with its picked plan" do
    create(:student_program, user: user, degree_program: major, catalog_year: catalog_year, plan_name: "Three Year Program")
    set

    expect(selection.entries).to eq([ [ set, "Three Year Program", user.student_programs.first ] ])
  end

  it "gives the program argument with no student row" do
    set

    expect(selection(program: "widget-design-bs").entries).to eq([ [ set, nil, nil ] ])
  end

  it "falls back to the standard plan for a renamed picked plan, but not for an unknown plan argument" do
    standard = create(:program_plan, requirement_set: set)

    expect(selection.plan(set, "Old Plan")).to eq(standard)
    expect { selection(plan: "Old Plan").plan(set, "Old Plan") }.to raise_error(AcademicProfiles::ProgramSelection::UnknownPlanError, /No plan Old Plan/)
  end
end
