# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermElectives::PdfParser do
  def parse(name)
    described_class.parse(file_fixture("term_electives/#{name}.txt").read)
  end

  def codes(result)
    result.courses.map { |course| [ "#{course.subject_code} #{course.course_number}", course.heading ] }
  end

  context "with bulleted lists for each program" do
    subject(:result) { parse("program_lists") }

    it "reads the title and the term" do
      expect(result).to have_attributes(title: "Spring 2031 School of Computing and Data Science Electives",
                                        season: "spring", year: 2031)
    end

    it "gives each course the nearest heading above it" do
      expect(codes(result)).to eq([
        [ "MGMT 1500", "Domain Electives" ],
        [ "MGMT 2000", "Domain Electives" ],
        [ "COMP 2000", "NET Elective" ],
        [ "MATH 4050", "NET Elective" ],
        [ "MATH 4050", "Data Science Elective" ],
        [ "COMP 2350", "Data Science Elective" ],
        [ "PHYS 1250", "Lab-based Science Electives (BSCN, BSCO)" ]
      ])
    end
  end

  context "with a table by area" do
    subject(:result) { parse("area_table") }

    it "uses the area as the heading, and skips the cells of each row" do
      expect(codes(result)).to eq([
        [ "ECON 4102", "Social Science" ],
        [ "PHIL 3800", "Humanities" ],
        [ "PHIL 4501", "Humanities" ]
      ])
      expect(result).to have_attributes(season: "spring", year: 2031)
    end
  end

  context "with a table of CRNs" do
    subject(:result) { parse("crn_table") }

    it "reads the subject column, and gives each course once" do
      expect(codes(result)).to eq([ [ "CRES 1000", nil ], [ "ECON 4102", nil ] ])
      expect(result).to have_attributes(season: "fall", year: 2030)
    end
  end

  context "with course descriptions" do
    subject(:result) { parse("descriptions") }

    it "does not take a line of a paragraph or a name as a heading" do
      expect(codes(result)).to eq([ [ "ARCH 3600", nil ], [ "ARCH 3800", nil ] ])
    end
  end

  it "gives no term when the text names none" do
    result = described_class.parse("Electives\n• COMP2000 – Data Structures\n")

    expect(result).to have_attributes(season: nil, year: nil, title: "Electives")
  end
end
