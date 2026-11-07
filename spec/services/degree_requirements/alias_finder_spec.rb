# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::AliasFinder do
  let(:old_year) { create(:catalog_year, start_year: 2014) }
  let(:new_year) { create(:catalog_year, start_year: 2015) }

  def catalog_course(year, code, title)
    subject_code, number = code.match(/([A-Z]+)(\d+)/).captures
    create(:catalog_year_course, catalog_year: year, subject_code: subject_code, course_number: number.to_i, title: title)
  end

  def banner_section(term, code, title)
    subject_code, number = code.match(/([A-Z]+)(\d+)/).captures
    create(:course, term: term, subject: subject_code, course_number: number.to_i, title: title)
  end

  def pairs = CourseCodeAlias.order(:from_course_number).map { |row| [ row.from_code, row.to_code, row.source ] }

  it "pairs the same subject and title in the 2014-2015 and 2015-2016 catalogs" do
    catalog_course(old_year, "COMP128", "Computer Science I")
    catalog_course(new_year, "COMP1000", "Computer Science I")
    catalog_course(old_year, "MATH205", "Intro to College Math &amp; Logic")
    catalog_course(new_year, "MATH1000", "Introduction to College Math and Logic")

    result = described_class.call

    expect(result).to have_attributes(added: 2, title_match: 2, banner: 0)
    expect(pairs).to eq([ [ "COMP 128", "COMP 1000", "title_match" ], [ "MATH 205", "MATH 1000", "title_match" ] ])
    expect(CourseCodeAlias.find_by(from_course_number: 128).note).to eq("2014-2015 and 2015-2016 catalogs: Computer Science I")
  end

  it "makes no pair from a title that names more than one course, or from another subject" do
    catalog_course(old_year, "COMP406", "Special Topics")
    catalog_course(old_year, "COMP407", "Special Topics")
    catalog_course(new_year, "COMP3800", "Special Topics")
    catalog_course(old_year, "ELEC231", "Network Theory I")
    catalog_course(new_year, "ELMC1000", "Network Theory I")

    expect(described_class.call.added).to eq(0)
  end

  it "pairs the old and new code of a Banner term that lists both" do
    term = create(:term, year: 2015, season: :fall)
    banner_section(term, "COMP570", "Database Applications")
    banner_section(term, "COMP4500", "Database Applications")

    expect(described_class.call).to have_attributes(added: 1, banner: 1)
    expect(pairs).to eq([ [ "COMP 570", "COMP 4500", "banner" ] ])
    expect(CourseCodeAlias.sole.note).to eq("Banner term #{term.uid}: Database Applications")
  end

  it "leaves a saved pair as it is, in either direction" do
    catalog_course(old_year, "COMP128", "Computer Science I")
    catalog_course(new_year, "COMP1000", "Computer Science I")
    reviewed = create(:course_code_alias, :reviewed, from_course_number: 128, to_course_number: 1000, source: "admin")

    expect(described_class.call.added).to eq(0)
    expect(reviewed.reload.source).to eq("admin")
  end

  it "does nothing without the two catalog years or Banner sections" do
    expect(described_class.call).to have_attributes(added: 0)
  end
end
