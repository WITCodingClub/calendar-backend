# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::ProgramMatcher do
  subject(:matcher) { described_class.new }

  let!(:science) { create(:degree_program, slug: "computer-science-bs", name: "Computer Science, B.S.") }
  let!(:science_masters) { create(:degree_program, :master, slug: "computer-science-ms", name: "Computer Science, M.S.") }
  let!(:architecture) { create(:degree_program, slug: "architecture-bs", name: "Architecture, B.S.") }
  let!(:architecture_masters) { create(:degree_program, :master, slug: "architecture-masters", name: "Architecture, M. Arch.") }
  let!(:engineering) { create(:degree_program, slug: "engineering-bs", name: "Engineering B.S.") }

  def program(title, code = nil)
    DegreeRequirements::PdfCatalog::Program.new(title: title, code: code, page: 1, plan: nil)
  end

  it "matches the subject and the kind from the program code" do
    expect(matcher.call(program("COMPUTER SCIENCE (BCOS)", "BCOS"))).to eq(science)
    expect(matcher.call(program("Computer Science (MSCS)", "MSCS"))).to eq(science_masters)
  end

  it "matches the degree words of the CourseLeaf contents" do
    expect(matcher.call(program("Computer Science Bachelor of Science"))).to eq(science)
    expect(matcher.call(program("MASTER OF ARCHITECTURE (ONE-YEAR) (MARC)", "MARC"))).to eq(architecture_masters)
  end

  it "matches a program that the catalog renamed" do
    expect(matcher.call(program("ENGINEERING-INTERDISCIPLINARY(BSEN)", "BSEN"))).to eq(engineering)
  end

  it "matches no program when the name fits more than one" do
    expect(matcher.call(program("ARCHITECTURE (TWO YEAR)"))).to be_nil
  end

  it "matches no program for a closed program or a missing name" do
    expect(matcher.call(program("COMPUTER ENGINEERING TECHNOLOGY (BCOT)", "BCOT"))).to be_nil
    expect(matcher.call(program(nil))).to be_nil
  end
end
