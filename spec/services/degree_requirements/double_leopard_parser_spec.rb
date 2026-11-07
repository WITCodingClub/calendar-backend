# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::DoubleLeopardParser do
  subject(:parser) { described_class.new(file_fixture("degree_requirements/double_leopard.html").read) }

  it "lists the program links under the Double Leopard heading once each, and no other link" do
    expect(parser.names).to eq([ "Widget Design", "Widget Design & Sprocket Management Dual Degree",
                                 "Gear and Cog Engineering", "Underwater Basketry" ])
  end

  it "reads the number of graduate courses a senior can take" do
    expect(parser.max_shared_courses).to eq(2)
    expect(described_class.new("<p>Take up to 3 courses</p>").max_shared_courses).to eq(3)
    expect(described_class.new("<p>No limit given</p>").max_shared_courses).to be_nil
  end

  it "lists nothing when the heading is gone" do
    expect(described_class.new("<h2>Programs</h2><a href='/academics/x'>X</a>").names).to be_empty
  end
end
