# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::CourseComparison do
  subject(:comparison) { described_class.new(catalog_year) }

  let(:catalog_year) { create(:catalog_year, :imported, start_year: 2024) }

  def year_course(number, **attributes)
    create(:catalog_year_course, catalog_year: catalog_year, subject_code: "COMP", course_number: number, **attributes)
  end

  def banner_course(number, **attributes)
    create(:catalog_course, subject_code: "COMP", course_number: number, **attributes)
  end

  def section(number, year:, season:)
    term = Term.find_by(year: year, season: season) || create(:term, year: year, season: season)
    create(:course, term: term, subject: "COMP", course_number: number)
  end

  it "lists a catalog course that Banner does not know" do
    year_course(1000, title: "COMPUTER SCIENCE I")

    expect(comparison.catalog_only.map(&:code)).to eq([ "COMP 1000" ])
    expect(comparison.catalog_only.first.catalog_title).to eq("COMPUTER SCIENCE I")
  end

  it "lists a Banner course with sections in the catalog year that the catalog leaves out" do
    banner_course(2000)
    banner_course(2001)
    banner_course(2002)
    section(2000, year: 2024, season: :fall)
    section(2001, year: 2025, season: :summer)
    section(2002, year: 2024, season: :spring) # 2023-2024, not this catalog year

    expect(comparison.banner_only.map(&:code)).to eq([ "COMP 2000", "COMP 2001" ])
  end

  it "leaves out a Banner course that the catalog year prints" do
    banner_course(2000)
    year_course(2000)
    section(2000, year: 2024, season: :fall)

    expect(comparison.banner_only).to be_empty
    expect(comparison.catalog_only).to be_empty
  end

  it "lists a title that differs in more than case and punctuation" do
    year_course(3000, title: "DATA STRUCTURES & ALGORITHMS")
    banner_course(3000, title: "Data Structures and Algorithms")
    year_course(3001, title: "OPERATING SYSTEMS")
    banner_course(3001, title: "Intro to Operating Systems")

    expect(comparison.title_differs.map(&:code)).to eq([ "COMP 3001" ])
    expect(comparison.title_differs.first).to have_attributes(catalog_title: "OPERATING SYSTEMS", banner_title: "Intro to Operating Systems")
  end

  it "lists Banner credits outside the catalog's range" do
    year_course(4000, min_credits: 3, max_credits: 4)
    banner_course(4000, credit_hours: 4)
    year_course(4001, min_credits: 4, max_credits: 4)
    banner_course(4001, credit_hours: 3)
    year_course(4002, min_credits: nil, max_credits: nil)
    banner_course(4002, credit_hours: 3)

    expect(comparison.credits_differ.map(&:code)).to eq([ "COMP 4001" ])
    expect(comparison.credits_differ.first).to have_attributes(catalog_credits: "4", banner_credits: 3)
  end

  it "counts each list" do
    year_course(1000)

    expect(comparison.counts).to eq(catalog_only: 1, banner_only: 0, title_differs: 0, credits_differ: 0)
  end

  it "refuses an unknown list" do
    expect { comparison.rows(:destroy) }.to raise_error(ArgumentError)
  end
end
