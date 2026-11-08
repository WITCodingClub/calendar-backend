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
      [ 1, "fall", "choice", "ENGR1600|ENGR1800", "Fundamentals of CAD or Programming with MATLAB", 1, 1 ],
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

  it "drops the repeated credits of a choice on a page with no break" do
    text = <<~TEXT
                                    TEST (BTST)
                            Fall Semester                     Spring Semester                  Summer Semester
                  ELECTIVE                           COMP1000                       4
                  General                            OR
                                                3    COMP1050                       4
                  TOTAL CREDITS                 3                                  4
    TEXT

    expect(rows(described_class.call(text).sole)).to eq([
      [ 1, "fall", "placeholder", nil, "General Elective", 3, 3 ],
      [ 1, "spring", "choice", "COMP1000|COMP1050", nil, 4, 4 ]
    ])
  end

  it "reads a choice with no second code, a subject with no number, and a science slot" do
    text = <<~TEXT
                                    TEST (BTST)
                            Fall Semester                         Spring Semester                     Summer Semester
                  MGMT ELECTIVE                    3-4    SCIENCE                          4    CIVE                             4
                  Concentration Course II OR              Science Elective                      Civil Engineering Capstone
                  Advanced Practicum                                                            Design
                  ELECTIVE                           3
                  General
                  TOTAL CREDITS                    6-7                                     4                                     4
    TEXT

    expect(rows(described_class.call(text).sole)).to eq([
      # The title ends in "OR", but the next line is the other name, not a code.
      [ 1, "fall", "placeholder", nil, "Concentration Course II or Advanced Practicum Elective", 3, 4 ],
      [ 1, "fall", "placeholder", nil, "General Elective", 3, 3 ],
      [ 1, "spring", "placeholder", nil, "Science Elective", 4, 4 ],
      # "CIVE" with no course number is a slot for a civil engineering course.
      [ 1, "summer", "placeholder", nil, "Civil Engineering Capstone Design", 4, 4 ]
    ])
  end

  describe "a table that a page break moves" do
    subject(:program) { described_class.call(file_fixture("degree_requirements/pdf/grid_page_break.txt").read).sole }

    it "places each column again on the new page, and reads codes the catalog writes in other ways" do
      expect(rows(program)).to eq([
        [ 1, "fall", "course", "MGMT1000", "Introduction to Management", 4, 4 ],
        # "Mechanical Graphics OR" over the next code.
        [ 1, "fall", "choice", "MECH124|MANF1000", "Mechanical Graphics or Manufacturing Processes", 4, 4 ],
        # A code with words after it, and a second code after "or" in the title.
        [ 1, "fall", "choice", "ENGR1600|ENGR1800", "Fundamentals of CAD & CAM", 1, 1 ],
        # "MGMTXXX" is a slot for any management course.
        [ 1, "spring", "placeholder", nil, "Information Systems Capstone", 4, 4 ],
        [ 1, "spring", "course", "TMGT8000", "Strategic Technology Business Management", 3, 3 ],
        [ 1, "spring", "course", "CONM3800", "Construction Management", 3, 3 ],
        [ 2, "fall", "course", "PHYS1000", "College Physics I", 4, 4 ],
        # A number alone on a line is credits, not a page number.
        [ 2, "fall", "placeholder", nil, "General Elective", 3, 3 ],
        # "CONMM 890" is a typo for CONM.
        [ 2, "spring", "course", "CONM890", "Capstone Research in CM", 3, 3 ],
        [ 2, "spring", "placeholder", nil, "Technical Elective II", 3, 4 ],
        [ 2, "summer", "course", "COOP3000", nil, 0, 0 ],
        [ 2, "summer", "course", "FMGT8900", "Optional Thesis", 6, 6 ]
      ])
    end
  end
end
