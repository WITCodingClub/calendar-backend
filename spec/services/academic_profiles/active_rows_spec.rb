# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::ActiveRows do
  let(:keys) { AcademicProfiles::CourseKeys.new({ [ "WDGT", 1000 ] => [ [ "WDGT", 100 ] ] }) }
  let(:major) do
    { program: "widget-design-bs", requirements: [
      { kind: "course", code: "WDGT 1000", status: "open", planned_term: "Fall 2026", planned_term_uid: 202710 },
      { kind: "placeholder", code: nil, course: "GIZM 2000", status: "done", planned_term: "Spring 2027", planned_term_uid: 202720 },
      { kind: "placeholder", code: nil, course: nil, status: "open" }
    ] }
  end
  let(:rows) { described_class.new([ major ], keys) }

  it "names the course of each row with its aliases, and skips a row that names none" do
    expect(rows.of(major).map { |row| [ row.keys.to_a, row.term_uid ] })
      .to eq([ [ [ [ "WDGT", 1000 ], [ "WDGT", 100 ] ], 202710 ], [ [ [ "GIZM", 2000 ] ], 202720 ] ])
  end

  it "leaves out the rows of the program itself" do
    expect(rows.other_than("widget-design-bs")).to be_empty
    expect(rows.other_than("gadget-minor").size).to eq(2)
  end

  it "marks the rows of a planned program that an active program also has, through an alias" do
    minor = { program: "gadget-minor", requirements: [
      { kind: "course", code: "WDGT 100", status: "open" },
      { kind: "choice", code: nil, options: [ "GIZM 3000", "GIZM 2000" ], status: "open" },
      { kind: "course", code: "GIZM 4000", status: "open" },
      { kind: "course", code: "GIZM 5000", status: "done" }
    ] }

    expect(rows.added_rows(minor).map { |added| [ added[:row][:code] || added[:row][:options], added[:shared] ] })
      .to eq([ [ "WDGT 100", true ], [ [ "GIZM 3000", "GIZM 2000" ], true ], [ "GIZM 4000", false ] ])
  end
end
