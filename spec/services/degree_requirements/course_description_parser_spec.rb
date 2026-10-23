# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CourseDescriptionParser do
  it "splits the description, prerequisites, credits, and terms" do
    result = described_class.call(JSON.parse(file_fixture("degree_requirements/course_details_wdgt3000.json").read)["description"])

    expect(result).to have_attributes(
      description: "Students make widgets spin. Topics include torque and balance.",
      prerequisite_text: "WDGT1000 (4 credits) and WDGT2000",
      min_credits: 3, max_credits: 4, typically_offered: %w[fall spring]
    )
  end

  it "reads a course with no prerequisites" do
    result = described_class.call("Counting with limits. This is a seven-week course. (2 credits) fall, spring, summer")

    expect(result).to have_attributes(description: "Counting with limits. This is a seven-week course.",
                                      prerequisite_text: nil, min_credits: 2, max_credits: 2,
                                      typically_offered: %w[fall spring summer])
  end

  it "reads one credit" do
    expect(described_class.call("Work term. (1 credit) summer")).to have_attributes(min_credits: 1, typically_offered: %w[summer])
  end

  it "returns nils for an empty description" do
    expect(described_class.call(nil)).to have_attributes(description: nil, min_credits: nil, typically_offered: [])
  end
end
