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
      # An HSS slot has four. 15 leaves 7 for one course, more than a course
      # has, so it stays without credits.
      [ 1, "spring", "course", "COMP1050", "Computer Science II", 4 ],
      [ 1, "spring", "course", "COMP1200", "Computer Organization", nil ],
      [ 1, "spring", "placeholder", nil, "HSS Elective", 4 ],
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
          # "OR" at the end of a line makes a choice with the next line. The
          # HSS slot has four, and the choice takes the 1 left.
          [ "MGMT2000", 3 ], [ "ENGR1800|ENGR1600", 1 ], [ "HSS Elective", 4 ] ],
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

    it "does not take them from the database for a semester with no total" do
      text = "Business Management (BSM)\nFreshman Year, Fall Semester\nMGMT1000, Introduction to Management\n"

      expect(credits(described_class.call(text, credits: { [ "MGMT", 1000 ] => 2 }))).to eq([ [ [ "MGMT1000", nil ] ] ])
    end

    it "does not take them from the database when only a remainder makes the total" do
      text = <<~TEXT
        Business Management (BSM)
        Freshman Year, Fall Semester (total credits 12)
        MGMT1000, Introduction to Management
        MATH1000, College Mathematics I
        PHYS1000, College Physics I
        MGMT ELECTIVE, Management Elective
      TEXT
      database = { [ "MGMT", 1000 ] => 4, [ "MATH", 1000 ] => 4, [ "PHYS", 1000 ] => 4 }

      # 12 left for the elective would be 0 credits: no value stays.
      expect(credits(described_class.call(text, credits: database)).first.map(&:last)).to eq([ nil, nil, nil, nil ])
    end

    it "does not take them from the database when the semester total disagrees" do
      database = { [ "MGMT", 2750 ] => 4, [ "MATH", 1000 ] => 3 }

      # 4 + 3 + 4 + 3 is not 15, so the rows take four each from the total.
      expect(credits(described_class.call(text, credits: database)).first.first(4)).to eq([
        [ "MGMT1000", 4 ], [ "MGMT1500", 3 ], [ "MGMT2750", 4 ], [ "MATH1000", 4 ]
      ])
    end
  end
  describe "rows that the catalog writes in other ways" do
    # The tabs and the page break are as pdftotext prints them.
    let(:text) do
      "Engineering (BSEN)\n" \
        "Freshman Year, Fall Semester (total credits 16)\n" \
        "ENGR1800                 Introduction to MATLAB (1 credit) Or ENGR1600 Fundamentals of CAD and CAM\n" \
        "(1 credit)\n" \
        "MATH1750                 Engineering Calculus I (4 credits)\n" \
        "MATH or SCIENCE          Math or Science Elective (4 credits)\n" \
        "EC \t\t                  Engineering Concentration (3 credits)\n" \
        "ENGINEERING COURSE (EC) Engineering Concentration (4 credits)\n" \
        "Freshman Year, Spring Semester (total credits 16)\n" \
        "EC, Engineering Concentration\n" \
        "MATH/SCIENCE, Math/Science Elective\n" \
        "MGMT1500/MATH1030, Decision Analysis for Business or Statistics\n" \
        "MGMT7000. Business Relations\n" \
        "ELECTIVE, Biomedical Engineering 4cr. ELECTIVE, Engineering 4cr.\n" \
        "COOP3500, Co-op Work Term IFreshman Year, Summer Semester (total credits 4)\n" \
        "HSS ELECTIVE, See ENGL/HSS note below *\n" \
        "                                     145\n" \
        "\f      Concentration Courses (Optional)\n" \
        "      MGMT2060               Introduction to Technology Project Management (3 credits)\n"
    end

    it "reads each of them as a row" do
      programs = described_class.call(text)

      # "EC, Engineering Concentration" is a row, not the name of a concentration.
      expect(programs.map(&:title)).to eq([ "Engineering (BSEN)" ])
      expect(rows(programs.sole)).to eq([
        # The credits of a row alone on the next line.
        [ 1, "fall", "choice", "ENGR1800|ENGR1600", "Introduction to MATLAB", 1 ],
        [ 1, "fall", "course", "MATH1750", "Engineering Calculus I", 4 ],
        [ 1, "fall", "placeholder", nil, "Math or Science Elective", 4 ],
        [ 1, "fall", "placeholder", nil, "Engineering Concentration", 3 ],
        [ 1, "fall", "placeholder", nil, "Engineering Concentration", 4 ],
        [ 1, "spring", "placeholder", nil, "Engineering Concentration", nil ],
        [ 1, "spring", "placeholder", nil, "Math/Science Elective", nil ],
        [ 1, "spring", "choice", "MGMT1500|MATH1030", "Decision Analysis for Business or Statistics", nil ],
        [ 1, "spring", "course", "MGMT7000", "Business Relations", nil ],
        # Two rows on one line.
        [ 1, "spring", "placeholder", nil, "Biomedical Engineering Elective", 4 ],
        [ 1, "spring", "placeholder", nil, "Engineering Elective", 4 ],
        # The next heading runs onto the end of this row.
        [ 1, "spring", "course", "COOP3500", "Co-op Work Term I", 0 ],
        # The list after the page break is not part of the plan.
        [ 1, "summer", "placeholder", nil, "HSS Elective", 4 ]
      ])
    end
  end

  describe "English and HSS slots" do
    let(:text) do
      <<~TEXT
        Business Management (BSM)
        Freshman Year, Fall Semester (total credits 14)
        MGMT2500, Systems Analysis and Design
        MGMT3250, Marketing
        HSS ELECTIVE, See ENGL/HSS note below *
        MGMT ELECTIVE, Concentration Course I
        Freshman Year, Spring Semester (total credits 17)
        ENGLISH, English Sequence
        MGMT1000, Introduction to Management (4 credits)
        MGMT1025, Introduction to Business (4 credits)
        MATH1000, College Mathematics I (4 credits)
      TEXT
    end

    def credits(programs) = rows(programs.sole).map { |row| [ row[3] || row[4], row[5] ] }

    it "have four credits, and the database credits leave one elective what the total leaves" do
      database = { [ "MGMT", 2500 ] => 3, [ "MGMT", 3250 ] => 4 }

      expect(credits(described_class.call(text, credits: database))).to eq([
        [ "MGMT2500", 3 ], [ "MGMT3250", 4 ], [ "HSS Elective", 4 ], [ "Concentration Course I Elective", 3 ],
        # 17 leaves 5, but an English slot has four.
        [ "English Sequence", 4 ], [ "MGMT1000", 4 ], [ "MGMT1025", 4 ], [ "MATH1000", 4 ]
      ])
    end

    it "include the Humanities/Social Science slot of the engineering plans" do
      text = <<~TEXT
        Engineering (BSEN)
        Freshman Year, Fall Semester (total credits 9)
        HUSS, Humanities/Social Science Elective*
        ENGR1000, Introduction to Engineering (4 credits)
      TEXT

      # 9 leaves 5, but the slot has four.
      expect(credits(described_class.call(text))).to eq([ [ "Humanities/Social Science Elective", 4 ], [ "ENGR1000", 4 ] ])
    end

    it "do not give a course a remainder that the database disagrees with" do
      text = <<~TEXT
        Engineering (BSEN)
        Freshman Year, Fall Semester (total credits 9)
        ENGLISH, English Sequence
        ENGR1000, Introduction to Engineering (4 credits)
        FYS1000, First Year Seminar
      TEXT

      # 1 left, but the database gives FYS1000 0: the total is wrong, not the course.
      expect(credits(described_class.call(text, credits: { [ "FYS", 1000 ] => 0 }))).to eq([
        [ "English Sequence", 4 ], [ "ENGR1000", 4 ], [ "FYS1000", nil ]
      ])
    end

    it "do not let the database leave an elective more than a course" do
      database = { [ "MGMT", 2500 ] => 1, [ "MGMT", 3250 ] => 4 }

      expect(credits(described_class.call(text, credits: database)).first(4).map(&:last)).to eq([ nil, nil, 4, nil ])
    end
  end
end
