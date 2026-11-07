# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::ListParser do
  subject(:programs) { described_class.call(file_fixture("degree_requirements/pdf/list.txt").read) }

  def rows(program)
    program.plan.items.map do |item|
      code = item.subject_code ? "#{item.subject_code}#{item.course_number}" : item.options.map(&:values).map(&:join).join("|")
      [ item.year_index, item.season, item.kind, code.presence, item.label, item.min_credits ]
    end
  end

  it "starts a program at each name with a code, and at a concentration" do
    expect(programs.map(&:title)).to eq([ "Computer Science (BCOS)", "Civil Engineering (BSCE)",
                                          "Architecture - Urbanism Concentration" ])
    expect(programs.map(&:code)).to eq([ "BCOS", "BSCE", nil ])
  end

  it "reads the courses under each semester heading" do
    expect(rows(programs.first)).to eq([
      # The semester total is four credits a course, so each gets four.
      [ 1, "fall", "course", "COMP1000", "Computer Science I", 4 ],
      [ 1, "fall", "course", "MATH2300", "Discrete Math", 4 ],
      [ 1, "fall", "course", "MATH1750", "Engineering Calculus I", 4 ],
      [ 1, "fall", "placeholder", nil, "English Sequence", 4 ],
      # 15 credits is not four a course, so only the printed credits stay.
      [ 1, "spring", "course", "COMP1050", "Computer Science II", 4 ],
      [ 1, "spring", "course", "COMP1200", "Computer Organization", nil ],
      [ 1, "spring", "placeholder", nil, "HSS Elective", nil ],
      [ 2, "summer", "course", "COOP3000", "Pre-Cooperative Work Term (Optional)", 0 ]
    ])
  end

  it "does not read the elective list after a plan as part of it" do
    codes = programs.first.plan.items.map(&:course_number)

    expect(codes).not_to include(3800)
  end

  it "reads printed credits, choices, and the four-credit default" do
    expect(rows(programs.second)).to eq([
      [ 1, "fall", "course", "MATH1750", "Engineering Calculus", 4 ],
      [ 1, "fall", "course", "FYS1000", "First Year Seminar", 0 ],
      [ 1, "fall", "choice", "ENGR1600|ENGR1800", "Fundamentals of CAD & CAM", 1 ],
      [ 1, "fall", "placeholder", nil, "Elective Biology or Geology", 4 ],
      [ 2, "fall", "choice", "CIVE2000|CIVE2005", "Statics and Mech Materials I", 3 ],
      # The catalog prints "Sophomore Year, Fall Semester" twice. The plan goes on.
      [ 2, "fall", "course", "CIVE2400", "Civil Engineering Materials", 3 ]
    ])
  end
end
