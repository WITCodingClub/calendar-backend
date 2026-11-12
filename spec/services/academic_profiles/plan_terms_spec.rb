# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::PlanTerms do
  # Fall 2025 start, Spring 2027 current: the registering term is Fall 2027.
  let(:start) { 202610 }
  let(:current) { 202720 }

  def row(year, season, status: "open", elective_list: nil)
    { year: year, season: season, kind: "course", code: "WDGT #{year}#{season.size}00", elective_list: elective_list, status: status }
  end

  def call(rows, start_term_uid: start, current_term_uid: current)
    described_class.new(start_term_uid, current_term_uid: current_term_uid).call({ program: "widget-design-bs", requirements: rows })
  end

  it "puts each plan semester in its real term, in plan order, with when and estimated" do
    rows = [ row(3, "fall"), row(1, "spring"), row(1, "fall"), row(2, "spring"), row(2, "summer"), row(3, "spring") ]

    result = call(rows)

    expect(result[:start_term]).to eq("Fall 2025")
    expect(result[:timeline].map { |semester| semester.values_at(:term, :uid, :year, :season, :when, :estimated) }).to eq(
      [
        [ "Fall 2025", 202610, 1, "fall", "past", false ],
        [ "Spring 2026", 202620, 1, "spring", "past", false ],
        [ "Spring 2027", 202720, 2, "spring", "current", false ],
        # A summer term between the current term and the registering term is future.
        [ "Summer 2027", 202730, 2, "summer", "future", false ],
        [ "Fall 2027", 202810, 3, "fall", "registering", true ],
        [ "Spring 2028", 202820, 3, "spring", "future", true ]
      ]
    )
    expect(result[:expected_end]).to eq(term: "Spring 2028", estimated: true)
  end

  it "marks a semester co-op only when every row is in the Co-op list" do
    co_op = DegreeRequirements::SharedElectives::CO_OP.name
    rows = [ row(3, "fall", elective_list: co_op), row(3, "spring", elective_list: co_op), row(3, "spring") ]

    expect(call(rows)[:timeline].map { |semester| semester.values_at(:term, :co_op) })
      .to eq([ [ "Fall 2027", true ], [ "Spring 2028", false ] ])
  end

  it "gives each row its planned term, and marks open rows of the current term or earlier behind" do
    rows = [ row(1, "fall"), row(1, "fall", status: "done"), row(1, "spring", status: "in_progress"), row(2, "spring"),
             row(3, "fall") ]

    expect(call(rows)[:requirements].map { |r| r.values_at(:planned_term, :planned_term_uid, :behind) }).to eq(
      [
        [ "Fall 2025", 202610, true ],
        [ "Fall 2025", 202610, false ],
        [ "Spring 2026", 202620, false ],
        [ "Spring 2027", 202720, true ],
        [ "Fall 2027", 202810, false ]
      ]
    )
  end

  it "gives a row with no plan semester no planned term, and never marks it behind" do
    list = { kind: "elective_list", elective_list: "Gear Electives", status: "open" }

    result = call([ list ])

    expect(result[:requirements].sole).to include(planned_term: nil, planned_term_uid: nil, behind: false)
    expect(result).to include(timeline: [], expected_end: nil)
  end

  it "has an empty timeline and no planned terms without a start term" do
    result = call([ row(1, "fall") ], start_term_uid: nil)

    expect(result).to include(start_term: nil, timeline: [], expected_end: nil)
    expect(result[:requirements].sole).to include(planned_term: nil, planned_term_uid: nil, behind: false)
  end

  it "has no when and no behind rows without a current term" do
    result = call([ row(1, "fall") ], current_term_uid: nil)

    expect(result[:timeline].sole).to include(term: "Fall 2025", when: nil)
    expect(result[:requirements].sole).to include(planned_term: "Fall 2025", behind: false)
  end

  it "uses the registering term of NextTermCourses: spring after a fall current term" do
    result = call([ row(2, "fall"), row(2, "spring") ], current_term_uid: 202710)

    expect(result[:timeline].pluck(:when)).to eq(%w[current registering])
  end
end
