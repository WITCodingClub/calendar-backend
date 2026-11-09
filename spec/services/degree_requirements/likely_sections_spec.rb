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

  it "returns nothing for no rows" do
    expect(likely.call([])).to eq({})
  end
end
