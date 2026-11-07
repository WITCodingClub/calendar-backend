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

  describe "credits that a row does not print" do
    let(:text) do
      <<~TEXT
        Business Management (BSM)
        Freshman Year, Fall Semester (total credits 15)
        MGMT1000, Introduction to Management 4 credits
        MGMT1500, Decision Analysis
        MGMT2750, Financial Accounting
        MATH1000, College Mathematics I

        Freshman Year, Spring Semester (total credits 8)
        MGMT2000, Information Systems
        ENGR1800, Introduction to MATLAB OR
        ENGR1600, Fundamentals of CAD & CAM
        HSS ELECTIVE

        Facility Management (BFPM)
        Freshman Year, Fall Semester (total credits 8)
        MGMT1500, Decision Analysis (3 credits)
        FMGT1000, Introduction to Facilities

        Management electives
        MGMT2000 Information Systems (3)
      TEXT
    end

    def credits(programs) = programs.map { |program| rows(program).map { |row| [ row[3] || row[4], row[5] ] } }

    it "takes them from another plan, a course list, and what the semester total leaves" do
      expect(credits(described_class.call(text))).to eq([
        # MGMT1500 takes 3 from the other plan, MGMT2000 from the list under it.
        # 15 - 7 leaves 8 for the two rows with no credits: four each.
        [ [ "MGMT1000", 4 ], [ "MGMT1500", 3 ], [ "MGMT2750", 4 ], [ "MATH1000", 4 ],
          # "OR" at the end of a line makes a choice with the next line.
          [ "MGMT2000", 3 ], [ "ENGR1800|ENGR1600", nil ], [ "HSS Elective", nil ] ],
        # FMGT1000 is the one row with no credits, so it takes the 5 left.
        [ [ "MGMT1500", 3 ], [ "FMGT1000", 5 ] ]
      ])
    end

    it "takes them from the database when the semester then adds up to its total" do
      database = { [ "MGMT", 2750 ] => 4, [ "MATH", 1000 ] => 4, [ "ENGR", 1600 ] => 1, [ "ENGR", 1800 ] => 1 }

      expect(credits(described_class.call(text, credits: database)).first).to eq([
        [ "MGMT1000", 4 ], [ "MGMT1500", 3 ], [ "MGMT2750", 4 ], [ "MATH1000", 4 ],
        # The choice takes 1 from the database, and the elective the 4 left.
        [ "MGMT2000", 3 ], [ "ENGR1800|ENGR1600", 1 ], [ "HSS Elective", 4 ]
      ])
    end

    it "does not take them from the database when the semester total disagrees" do
      database = { [ "MGMT", 2750 ] => 4, [ "MATH", 1000 ] => 3 }

      # 4 + 3 + 4 + 3 is not 15, so the rows take four each from the total.
      expect(credits(described_class.call(text, credits: database)).first.first(4)).to eq([
        [ "MGMT1000", 4 ], [ "MGMT1500", 3 ], [ "MGMT2750", 4 ], [ "MATH1000", 4 ]
      ])
    end
  end
end
