# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfGridParser do
  subject(:result) { described_class.call(file_fixture("degree_requirements/pdf_grid.txt").read) }

  let(:plan) { result.plans.first }

  def row(year, season, position)
    plan.items.select { |item| item.year_index == year && item.season == season }[position]
  end

  it "reads the plan under its program name" do
    expect(result.plans.map(&:heading)).to eq([ "WIDGET DESIGN (BWID)" ])
    expect(plan).to have_attributes(years: 2, total_credits: 40)
  end

  it "puts each row in the semester of its column, in order" do
    expect(plan.items.map { |item| [ item.year_index, item.season, item.subject_code, item.course_number ] }).to eq(
      [
        [ 1, "fall", "WDGT", 101 ], [ 1, "fall", "MATH", 205 ], [ 1, "fall", nil, nil ],
        [ 1, "spring", "WDGT", 102 ], [ 1, "spring", nil, nil ], [ 1, "spring", nil, nil ],
        [ 2, "fall", "WDGT", 201 ], [ 2, "fall", nil, nil ],
        [ 2, "spring", "COOP", 400 ],
        [ 2, "summer", "WDGT", 260 ], [ 2, "summer", nil, nil ]
      ]
    )
  end

  it "joins a title over several lines and across the year label" do
    expect(row(1, "fall", 0)).to have_attributes(kind: "course", title: "Introduction to Widget Design", min_credits: 4)
  end

  it "reads a placeholder and its label" do
    expect(row(1, "fall", 2)).to have_attributes(kind: "placeholder", label: "English Sequence")
    expect(row(2, "fall", 1)).to have_attributes(kind: "placeholder", label: "Humanities or Social Science Elective")
    expect(row(2, "summer", 1)).to have_attributes(label: "Widget Design Elective")
  end

  it "reads two codes with or between them as a choice" do
    expect(row(1, "spring", 1)).to have_attributes(
      kind: "choice", options: [ { "subject_code" => "WDGT", "course_number" => 150 },
                                 { "subject_code" => "WDGT", "course_number" => 160 } ]
    )
  end

  it "reads the rows after a page footer" do
    expect(row(2, "summer", 0)).to have_attributes(subject_code: "WDGT", course_number: 260, title: "Widget Studio II")
  end

  # The catalogs have such typos, so the plan is kept with a warning.
  it "warns when a printed total does not match its rows" do
    expect(plan.warnings).to eq([ "Year 2 fall: the rows add up to 8 credits, the printed total is 10." ])
  end

  it "leaves out a plan with credits that belong to no code" do
    expect(result.rejections).to contain_exactly(
      have_attributes(heading: "GADGET STUDIES (BGAD)", reason: "credits with no code: 6")
    )
  end

  it "leaves out a plan whose year label does not count up" do
    text = [
      "                  WIDGET DESIGN (BWID)",
      "            Fall Semester                    Spring Semester",
      "        Course                    Credits   Course                 Credits",
      "        WDGT101                        4    WDGT102                     4",
      "        Widget Design I                     Widget Design II",
      " Junior Year",
      "                                      4                                4"
    ].join("\n")

    expect(described_class.call(text).rejections.map(&:reason)).to eq([ "year 1 has the label Junior Year" ])
  end
end
