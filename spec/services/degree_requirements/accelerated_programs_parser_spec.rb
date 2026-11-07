# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::AcceleratedProgramsParser do
  subject(:parser) { described_class.new(file_fixture("degree_requirements/accelerated_programs.html").read) }

  it "lists each option with two or more programs, with the program slugs in order" do
    expect(parser.entries.map { |entry| [ entry.name, entry.slugs ] }).to eq(
      [
        [ "Widget Design, B.S. and Master of Widget Design 5-Year", %w[widget-design-bs widget-design-ms] ],
        [ "Gear Studies, B.S. and Gear Studies, M.S. 5-Year", %w[gear-studies-bs gear-studies-ms] ],
        [ "Master of Widget Design (One Year) and Master of Sprocket Management 2-Year",
          %w[widget-design-ms sprocket-management-masters] ]
      ]
    )
  end

  it "lists nothing for a page with no catalog text" do
    expect(described_class.new("<html><body><p><a href='/a/'>A</a><a href='/b/'>B</a></p></body></html>").entries).to be_empty
  end
end
