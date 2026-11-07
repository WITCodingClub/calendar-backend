# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::ProgramMerge do
  let(:old) { create(:degree_program, slug: "widget-design-program", name: "Widget Design Bachelor of Science") }
  let(:current) { create(:degree_program, slug: "widget-design-bs", name: "Widget Design, B.S.") }

  def merge = described_class.call("widget-design-program", "widget-design-bs")

  it "moves the catalog years, pathway steps, student links and concentrations, then deletes the old program" do
    old_set = create(:requirement_set, degree_program: old, catalog_year: create(:catalog_year, start_year: 2019))
    create(:requirement_set, degree_program: current, catalog_year: create(:catalog_year, start_year: 2024))
    step = create(:program_pathway_step, degree_program: old)
    student_program = create(:student_program, degree_program: old)
    concentration = create(:degree_program, :concentration, parent_program: old)

    expect(merge).to have_attributes(status: :merged, moved_sets: 1)

    expect(DegreeProgram.exists?(old.id)).to be(false)
    expect(old_set.reload.degree_program).to eq(current)
    expect(current.requirement_sets.count).to eq(2)
    expect(step.reload.degree_program).to eq(current)
    expect(student_program.reload.degree_program).to eq(current)
    expect(concentration.reload.parent_program).to eq(current)
  end

  it "gives the old program the new slug when no program has it" do
    old

    expect(merge.status).to eq(:renamed)
    expect(old.reload.slug).to eq("widget-design-bs")
  end

  it "does nothing when no program has the old slug" do
    expect(merge.status).to eq(:nothing)
  end

  it "stops and changes nothing when both programs have a set for the same year" do
    year = create(:catalog_year, start_year: 2024)
    create(:requirement_set, degree_program: old, catalog_year: year)
    create(:requirement_set, degree_program: current, catalog_year: year)

    expect { merge }.to raise_error(DegreeRequirements::Error, /both have a different set for 2024/)
    expect(old.reload.requirement_sets.count).to eq(1)
  end

  it "drops the copy on the old program of a set from the same page" do
    year = create(:catalog_year, start_year: 2025)
    create(:requirement_set, degree_program: old, catalog_year: year, source_digest: "abc")
    kept = create(:requirement_set, degree_program: current, catalog_year: year, source_digest: "abc")

    expect(merge).to have_attributes(status: :merged, moved_sets: 0)
    expect(current.requirement_sets).to eq([ kept ])
  end

  it "merges every renamed program, and goes on after one that stops" do
    stub_const("DegreeProgram::RENAMED_SLUGS", { "widget-design-program" => "widget-design-bs", "gear-program" => "gear-bs" })
    year = create(:catalog_year, start_year: 2024)
    create(:requirement_set, degree_program: old, catalog_year: year)
    create(:requirement_set, degree_program: current, catalog_year: year)
    gear = create(:degree_program, slug: "gear-program")
    allow(Rails.error).to receive(:report)

    results = described_class.renamed

    expect(results.map(&:status)).to eq(%i[stopped renamed])
    expect(gear.reload.slug).to eq("gear-bs")
    expect(Rails.error).to have_received(:report).with(an_instance_of(DegreeRequirements::Error), hash_including(handled: true))
  end
end
