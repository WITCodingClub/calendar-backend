# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PathwaySeed do
  let(:path) { file_fixture("degree_requirements/program_pathways.yml") }
  let!(:widget_bs) { create(:degree_program, slug: "widget-design-bs") }
  let!(:widget_ms) { create(:degree_program, :master, slug: "widget-design-ms") }

  def seed = described_class.new(path: path).call

  it "creates each pathway with its steps in order, and skips one with a program that is not imported yet" do
    result = seed

    pathway = ProgramPathway.find_by!(slug: "widget-design-4-plus-1")
    expect(pathway).to have_attributes(kind: "four_plus_one", max_shared_courses: 2, max_shared_credits: nil, active: true)
    expect(pathway.steps.map { |step| [ step.degree_program, step.plan_years, step.position ] })
      .to eq([ [ widget_bs, 4, 1 ], [ widget_ms, 1, 2 ] ])
    expect(result).to have_attributes(saved: [ "widget-design-4-plus-1" ], skipped: [ "gear-studies-3-plus-1" ])
    expect(ProgramPathway.exists?(slug: "gear-studies-3-plus-1")).to be(false)
  end

  it "keeps the steps when nothing changed, and adds a skipped pathway once its programs exist" do
    seed
    step_ids = ProgramPathwayStep.ids
    create(:degree_program, slug: "gear-studies-bs")
    create(:degree_program, :master, slug: "gear-studies-ms")

    seed

    expect(ProgramPathwayStep.where(id: step_ids).count).to eq(2)
    expect(ProgramPathway.find_by!(slug: "gear-studies-3-plus-1")).to have_attributes(kind: "three_plus_one", max_shared_credits: 8)
  end

  it "replaces the steps when a step changes" do
    seed
    ProgramPathwayStep.find_by!(degree_program: widget_bs).update!(plan_years: 5)

    seed

    expect(ProgramPathway.find_by!(slug: "widget-design-4-plus-1").steps.map(&:plan_years)).to eq([ 4, 1 ])
  end

  it "sets a pathway that left the file inactive, and keeps the planned programs that link to it" do
    old = create(:program_pathway, slug: "old-pathway-4-plus-1")
    planned = create(:student_program, :planned, program_pathway: old)

    expect(seed.deactivated).to eq(1)
    expect(old.reload.active).to be(false)
    expect(planned.reload.program_pathway).to eq(old)
  end

  it "raises for an entry with a missing field or fewer than two steps" do
    bad = Rails.root.join("tmp/pathway_seed_bad_#{Process.pid}.yml")
    File.write(bad, [ { "slug" => "x", "name" => "X", "kind" => "four_plus_one", "steps" => [ { "program" => "a" } ] } ].to_yaml)

    expect { described_class.new(path: bad).call }.to raise_error(described_class::InvalidSeedError, /needs steps/)
  ensure
    FileUtils.rm_f(bad)
  end

  it "raises InvalidSeedError for a file that does not parse and for a step that is not a map" do
    bad = Rails.root.join("tmp/pathway_seed_syntax_#{Process.pid}.yml")
    File.write(bad, "- slug: [unclosed\n")
    expect { described_class.entries(bad) }.to raise_error(described_class::InvalidSeedError)

    File.write(bad, [ { "slug" => "x", "name" => "X", "kind" => "four_plus_one", "steps" => %w[a b] } ].to_yaml)
    expect { described_class.entries(bad) }.to raise_error(described_class::InvalidSeedError, /must be a map/)
  ensure
    FileUtils.rm_f(bad)
  end

  # config/program_pathways.yml is the real list, so a typo there should fail
  # here and not only in production.
  it "reads config/program_pathways.yml with valid kinds and unique slugs" do
    entries = described_class.entries

    expect(entries).not_to be_empty
    expect(entries.pluck("slug")).to eq(entries.pluck("slug").uniq)
    expect(entries.pluck("kind") - ProgramPathway::KINDS.values).to be_empty
  end
end
