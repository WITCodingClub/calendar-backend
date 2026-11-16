# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::DegreeProgressRequest do
  it "refuses catalog_year or plan without program" do
    expect { described_class.new(program: nil, catalog_year: "2025-2026", plan: nil) }
      .to raise_error(described_class::InvalidArgumentsError, "catalog_year and plan need program")
    expect { described_class.new(program: "", catalog_year: nil, plan: "Three Year Program") }
      .to raise_error(AcademicProfiles::PlanningError)
  end

  it "passes the arguments to DegreeProgress" do
    user = build(:user)
    progress = instance_double(AcademicProfiles::DegreeProgress, call: { programs: [] })
    allow(AcademicProfiles::DegreeProgress).to receive(:new).and_return(progress)

    result = described_class.new(program: "widget-design-bs", catalog_year: "2025-2026", plan: nil, include_planned: true).call(user)

    expect(result).to eq(programs: [])
    expect(AcademicProfiles::DegreeProgress).to have_received(:new)
      .with(user, program: "widget-design-bs", catalog_year: "2025-2026", plan: nil, include_planned: true)
  end
end
