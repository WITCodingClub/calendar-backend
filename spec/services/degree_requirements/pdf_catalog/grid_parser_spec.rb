# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::GridParser do
  subject(:programs) { described_class.call(file_fixture("degree_requirements/pdf/grid.txt").read) }

  let(:science) { programs.first }
  let(:electrical) { programs.second }

  def rows(program)
    program.plan.items.map do |item|
      code = item.subject_code ? "#{item.subject_code}#{item.course_number}" : item.options.map(&:values).map(&:join).join("|")
      [ item.year_index, item.season, item.kind, code.presence, item.label, item.min_credits, item.max_credits ]
    end
  end

  it "reads each plan table with the program in its heading" do
    expect(programs.map(&:title)).to eq([ "COMPUTER SCIENCE (BCOS)", "ELECTRICAL ENGINEERING (BSEE)" ])
    expect(programs.map(&:code)).to eq(%w[BCOS BSEE])
    expect(science.plan).to have_attributes(name: "Computer Science (BCOS)", years: 2, total_credits: 39, accelerated: false)
  end

  it "gives the PDF page each table starts on" do
    expect(programs.map(&:page)).to eq([ 2, 3 ])
  end

  it "reads the cells of each column as the rows of a semester" do
    expect(rows(science)).to eq([
      [ 1, "fall", "course", "COMP128", "Computer Science I", 4, 4 ],
      [ 1, "fall", "course", "MATH205", "College Math I", 4, 4 ],
      [ 1, "fall", "placeholder", nil, "English Sequence", 4, 4 ],
      [ 1, "spring", "course", "COMP201", "Computer Science II", 4, 4 ],
      [ 1, "spring", "course", "MATH250", "Precalculus", 4, 4 ],
      [ 1, "spring", "placeholder", nil, "Humanities or Social Science Elective", 4, 4 ],
      # The rest of the year is on the next page, ten characters further left.
      [ 2, "fall", "course", "COMP285", "Object Oriented Programming", 4, 4 ],
      [ 2, "fall", "choice", "MATH181|MATH250", "Statistics", 4, 4 ],
      [ 2, "spring", "course", "COMP355", "Database Management Systems", 4, 4 ],
      [ 2, "spring", "placeholder", nil, "Computer Science Elective", 3, 4 ],
      [ 2, "summer", "course", "COOP300", "Pre-Cooperative Work Term (Optional)", 0, 0 ]
    ])
  end

  it "keeps the footnote mark of a placeholder" do
    expect(science.plan.items.find { |item| item.label.start_with?("Humanities") }.footnote).to eq("*")
  end

  it "reads credits on their own line and an OR between two cells" do
    expect(rows(electrical)).to eq([
      [ 1, "fall", "placeholder", nil, "English Sequence", 4, 4 ],
      [ 1, "fall", "choice", "ENGR1600|ENGR1800", "Fundamentals of CAD Programming with MATLAB", 1, 1 ],
      [ 1, "spring", "course", "MATH1850", "Engineering Calculus", 3, 3 ],
      [ 1, "spring", "course", "PHYS1750", "Engineering Physics II", 4, 4 ]
    ])
  end

  it "stops at the text under a table" do
    labels = programs.flat_map { |program| program.plan.items.map(&:label) }

    expect(labels.join(" ")).not_to match(/Minor|FACULTY|Instructors/)
  end

  it "reads nothing from text with no plan" do
    expect(described_class.call("Fall Semester is the first term.\nNo table here.")).to eq([])
  end
end
