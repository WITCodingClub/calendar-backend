# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::LikelySections do
  subject(:likely) { described_class.new(catalog_year) }

  let(:catalog_year) { create(:catalog_year, :imported, start_year: 2026) }

  def row(code, title)
    DegreeRequirements::CourseComparison::Row.new(code: code, catalog_title: title, banner_title: nil,
                                                 catalog_credits: nil, banner_credits: nil)
  end

  def section(subject, number, title, year: 2025, season: :fall)
    term = Term.find_by(year: year, season: season) || create(:term, year: year, season: season)
    create(:course, term: term, subject: subject, course_number: number, title: title)
  end

  it "finds a special topics section with the same title" do
    section("Computer Science (COMP)", 7800, "Natural Language Processing")

    match = likely.call([ row("COMP 5100", "NATURAL LANGUAGE PROCESSING") ])["COMP 5100"].sole

    expect(match).to have_attributes(code: "COMP 7800", title: "Natural Language Processing", kind: :special_topics,
                                     last_term: "Fall 2025", sections: 1)
  end

  it "calls the same number in another subject a same-number match" do
    section("Cybersecurity (CYBR)", 6520, "Malware Analysis")

    expect(likely.call([ row("COMP 6520", "MALWARE ANALYSIS") ])["COMP 6520"].map(&:kind)).to eq([ :same_number ])
  end

  it "matches a lab section and a title cut short" do
    section("Computer Science (COMP)", 3800, "Software Security - Lab")
    section("Computer Science (COMP)", 4750, "Embedded Artificial Intelligen")

    result = likely.call([ row("COMP 3600", "SOFTWARE SECURITY"), row("COMP 5750", "EMBEDDED ARTIFICIAL INTELLIGENCE") ])

    expect(result["COMP 3600"].map(&:code)).to eq([ "COMP 3800" ])
    expect(result["COMP 5750"].map(&:kind)).to eq([ :other_number ])
  end

  it "leaves out sections older than the recent academic years, and different titles" do
    section("Computer Science (COMP)", 7800, "Natural Language Processing", year: 2021, season: :fall)
    section("Computer Science (COMP)", 7800, "Computer Graphics")

    expect(likely.call([ row("COMP 5100", "NATURAL LANGUAGE PROCESSING") ])).to eq({})
  end

  it "counts the sections of a code and gives the last term" do
    section("Computer Science (COMP)", 7800, "Natural Language Processing", year: 2023, season: :fall)
    section("Computer Science (COMP)", 7800, "Natural Language Processing", year: 2026, season: :spring)

    match = likely.call([ row("COMP 5100", "NATURAL LANGUAGE PROCESSING") ])["COMP 5100"].sole

    expect(match).to have_attributes(sections: 2, last_term: "Spring 2026")
  end

  # pg_trgm gives "calculus i" and "calculus ii" 0.77.
  it "does not match another place in a sequence, and reads 2 as II" do
    section("Electrical Engineering (ELEC)", 6000, "Power Systems Analysis I")
    section("Electrical Engineering (ELEC)", 7800, "Power System Analysis 2")

    result = likely.call([ row("ELEC 5660", "POWER SYSTEMS ANALYSIS II") ])["ELEC 5660"]

    expect(result.map(&:code)).to eq([ "ELEC 7800" ])
  end

  it "removes a lab suffix from both titles, but keeps Matlab whole" do
    section("Mechanical Engineering (MECH)", 3800, "Intermediate Matlab")
    section("Mechanical Engineering (MECH)", 2750, "Thermodynamics_lab")

    result = likely.call([ row("MECH 3250", "INTERMEDIATE MATLAB"), row("MECH 2275", "THERMODYNAMICS LAB") ])

    expect(result["MECH 3250"].map(&:code)).to eq([ "MECH 3800" ])
    expect(result["MECH 2275"].map(&:code)).to eq([ "MECH 2750" ])
  end

  it "calls a same-number match with a weaker title a similar title" do
    section("Engineering (ENGR)", 1000, "Introduction To Engineering")

    match = likely.call([ row("BMED 1000", "INTRODUCTION TO BIOMEDICAL ENGINEERING") ])["BMED 1000"].sole

    expect(match.kind).to eq(:other_number)
  end

  it "returns nothing for no rows" do
    expect(likely.call([])).to eq({})
  end
end
