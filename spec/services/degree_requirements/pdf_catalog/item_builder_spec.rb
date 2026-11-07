# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::ItemBuilder do
  def build(code, title = "", credits = nil) = described_class.build(code, title, credits, year_index: 1, season: "fall")

  describe ".code?" do
    it "accepts course codes and placeholder words" do
      expect(%w[COMP128 COMP1000 ELECTIVE ENGLISH]).to all(satisfy { |text| described_class.code?(text) })
      expect(described_class.code?("HSS ELECTIVE")).to be(true)
      expect(described_class.code?("COMP1100 or COMP2100")).to be(true)
      expect(described_class.code?("ELECTIVE*")).to be(true)
    end

    it "refuses headings and titles in capitals" do
      expect(%w[FACULTY MATLAB TOTAL]).to all(satisfy { |text| !described_class.code?(text) })
      expect(described_class.code?("TOTAL CREDITS")).to be(false)
    end
  end

  it "builds a course row" do
    expect(build("COMP 1000", "Computer Science I", 4).first)
      .to have_attributes(kind: "course", subject_code: "COMP", course_number: 1000, label: "Computer Science I",
                          min_credits: 4, max_credits: 4)
  end

  it "builds a choice row" do
    item = build("COMP1000/ELEC3150", "Programming", "4").first

    expect(item).to have_attributes(kind: "choice", subject_code: nil)
    expect(item.options).to eq([ { "subject_code" => "COMP", "course_number" => 1000 },
                                 { "subject_code" => "ELEC", "course_number" => 3150 } ])
  end

  it "builds a row with no credits for each course of a pair" do
    items = build("MATH1776 & MATH1777", "Calculus", 4)

    expect(items.map(&:course_number)).to eq([ 1776, 1777 ])
    expect(items.map(&:min_credits)).to eq([ nil, nil ])
  end

  it "reads a credit range" do
    expect(build("ELECTIVE", "Architecture", "3-4").first).to have_attributes(min_credits: 3, max_credits: 4)
  end

  it "names placeholders" do
    expect(build("ELECTIVE", "Humanities or Social Science").first.label).to eq("Humanities or Social Science Elective")
    expect(build("ENGLISH", "English Sequence").first.label).to eq("English Sequence")
    expect(build("HSS ELECTIVE", "See ENGL/HSS note below *").first.label).to eq("HSS Elective")
    expect(build("TECHNICAL ELECTIVE").first.label).to eq("Technical Elective")
  end

  it "keeps the footnote mark of a code" do
    expect(build("ELECTIVE*", "Humanities").first.footnote).to eq("*")
  end

  it "adds the minimum credits of the rows" do
    items = build("COMP128", "", 4) + build("ELECTIVE", "", "3-4") + build("MATH1776 & MATH1777")

    expect(described_class.total_credits(items)).to eq(7)
    expect(described_class.total_credits(build("MATH1776 & MATH1777"))).to be_nil
  end
end
