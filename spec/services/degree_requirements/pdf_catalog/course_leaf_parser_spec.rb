# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::CourseLeafParser do
  subject(:programs) { described_class.call(file_fixture("degree_requirements/pdf/courseleaf.txt").read) }

  let(:science) { programs.first }

  it "names the program from the table of contents and the printed page number" do
    expect(science).to have_attributes(title: "Computer Science Bachelor of Science", page: 3)
    expect(science.plan).to have_attributes(name: "Four Year Program", years: 2, total_credits: 20)
  end

  it "reads courses, choices, pairs, placeholders, and titles over two lines" do
    rows = science.plan.items.map do |item|
      code = item.subject_code ? "#{item.subject_code}#{item.course_number}" : item.options.map(&:values).map(&:join).join("|")
      [ item.year_index, item.season, item.kind, code.presence, item.label, item.min_credits ]
    end

    expect(rows).to eq([
      [ 1, "fall", "course", "COMP1000", "Computer Science I", 4 ],
      [ 1, "fall", "choice", "COMP1100|COMP2100", "Networking", 4 ],
      [ 1, "fall", "course", "MATH1776", "Calculus A and B", nil ],
      [ 1, "fall", "course", "MATH1777", "Calculus A and B", nil ],
      [ 1, "fall", "placeholder", nil, "HSS Elective", 4 ],
      [ 1, "spring", "course", "COMP1050", "Computer Science II", 4 ],
      [ 2, "summer", "choice", "COMP2000|COMP2005", "Data Structures and Algorithms", 4 ]
    ])
    expect(science.plan.items.find { |item| item.kind == "placeholder" }.footnote).to eq("*")
  end

  it "gives each plan the lines of its rows in the whole text, past form feeds" do
    text = file_fixture("degree_requirements/pdf/courseleaf.txt").read
    lines = text.split("\n")

    programs.each do |program|
      expect(lines[program.lines.begin]).to match(/First Year/)
      expect(lines[program.lines.end]).to match(/\S/)
    end
  end

  it "ends a plan with no total at its last row, not at a list under it" do
    text = <<~TEXT
      First Year
      Fall Semester                                   Credits
      COMP1000         COMPUTER SCIENCE I                 4
      \fComputer Science Electives:
    TEXT

    expect(described_class.call(text).sole.lines).to eq(0..2)
  end

  it "ends a plan with no total at the first year of the next plan" do
    text = file_fixture("degree_requirements/pdf/courseleaf.txt").read.sub(/^ +Total Credits +24\n/, "")

    plans = described_class.call(text)

    expect(plans.map { |program| program.plan.items.size }).to eq([ 7, 1 ])
  end

  it "gives no program to a plan under a department heading" do
    expect(programs.second.title).to be_nil
  end

  context "with programs that share a page" do
    subject(:programs) { described_class.call(file_fixture("degree_requirements/pdf/courseleaf_shared_pages.txt").read) }

    it "names each plan from the heading above it and joins contents entries over two lines" do
      expect(programs.map(&:title)).to eq([
        "Biological Engineering Bachelor of Science",
        "Engineering Bachelor of Science with a Concentration in Biomedical Engineering",
        "Engineering Bachelor of Science with a Concentration in Civil Engineering",
        "Engineering - Robotics, B.S."
      ])
    end

    it "gives no program when no heading names one of the programs on the page" do
      text = file_fixture("degree_requirements/pdf/courseleaf_shared_pages.txt").read
                                                                               .sub("Engineering - Robotics, B.S.\n", "")

      expect(described_class.call(text).last.title).to be_nil
    end

    it "does not take a program named inside a sentence" do
      text = file_fixture("degree_requirements/pdf/courseleaf_shared_pages.txt").read
                                                                               .sub("Engineering - Robotics, B.S.\n", "Students can add the Robotics Minor.\n")

      expect(described_class.call(text).last.title).to be_nil
    end

    it "gives no program to a plan before the first contents entry" do
      text = file_fixture("degree_requirements/pdf/courseleaf_shared_pages.txt").read
                 .gsub(/\.{4,} (\d)$/) { "..... #{Regexp.last_match(1).to_i + 5}" }

      expect(described_class.call(text).map(&:title)).to all(be_nil)
    end
  end
end
