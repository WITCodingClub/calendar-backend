# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::PlanEstimate do
  # Fall 2025 start. The current term is Fall 2026 unless an example says
  # otherwise, so the first term of the estimate is Spring 2027.
  let(:start) { 202610 }
  let(:current) { 202710 }
  let(:trees) { {} }
  let(:prerequisites) do
    trees_by_pair = trees
    Class.new { define_method(:prerequisites) { |pair| trees_by_pair[pair] } }.new
  end

  # A course row in plan year and season. term: the label of the term the
  # student took it (done) or takes it (in_progress).
  def course(code, year, season, status: "open", term: nil, credits: 4, offered: nil, kind: "course")
    { year: year, season: season, kind: kind, code: code, options: [], elective_list: nil, status: status, term: term,
      credit_hours: credits, typically_offered: offered }
  end

  def requires(*codes)
    operands = codes.map do |code|
      subject, number = code.split
      { "type" => "course", "subject_code" => subject, "course_number" => number }
    end
    operands.one? ? operands.first : { "type" => "and", "operands" => operands }
  end

  def estimate(rows, current_term_uid: current)
    entry = AcademicProfiles::PlanTerms.new(start, current_term_uid: current_term_uid).call({ requirements: rows })
    described_class.new(start, current_term_uid: current_term_uid, prerequisites: prerequisites).call(entry)
  end

  def placed(result)
    result[:requirements].to_h { |row| [ row[:code], row.values_at(:expected_term, :moved) ] }
  end

  def timeline(result) = result[:timeline].map { |term| term.values_at(:term, :basis, :co_op) }

  it "keeps every row in its plan term for a student who follows the plan exactly" do
    trees[[ "WDGT", 1200 ]] = requires("WDGT 1100")
    trees[[ "COOP", 3500 ]] = requires("COOP 2500")
    rows = [
      course("WDGT 1100", 1, "fall", status: "done", term: "Fall 2025"),
      course("WDGT 1101", 1, "fall", status: "done", term: "Fall 2025"),
      course("WDGT 1200", 1, "spring", status: "done", term: "Spring 2026"),
      course("WDGT 1201", 1, "spring", status: "done", term: "Spring 2026"),
      course("WDGT 2100", 2, "fall", status: "in_progress", term: "Fall 2026"),
      course("COOP 2500", 2, "fall", status: "in_progress", term: "Fall 2026", credits: 1),
      course("WDGT 2200", 2, "spring", offered: %w[spring]),
      course("WDGT 2201", 2, "spring"),
      course("COOP 3500", 2, "summer", credits: 0),
      course("WDGT 3100", 3, "fall", offered: %w[fall]),
      course("WDGT 3101", 3, "fall"),
      course("COOP 4500", 3, "spring", credits: 0),
      course("WDGT 3300", 3, "summer"),
      course("WDGT 4100", 4, "fall"),
      course("WDGT 4101", 4, "fall")
    ]

    result = estimate(rows)

    result[:requirements].each do |row|
      expect(row).to include(expected_term: row[:planned_term], expected_term_uid: row[:planned_term_uid], moved: nil)
    end
    expect(result[:expected_end]).to eq(term: "Fall 2028", estimated: true, plan_end: "Fall 2028")
    expect(result[:timeline].map { |term| term.values_at(:term, :uid, :year, :season, :basis, :co_op) }).to eq(
      [
        [ "Fall 2025", 202610, 1, "fall", "taken", false ],
        [ "Spring 2026", 202620, 1, "spring", "taken", false ],
        [ "Fall 2026", 202710, 2, "fall", "taken", false ],
        [ "Spring 2027", 202720, 2, "spring", "plan", false ],
        [ "Summer 2027", 202730, 2, "summer", "plan", true ],
        [ "Fall 2027", 202810, 3, "fall", "plan", false ],
        [ "Spring 2028", 202820, 3, "spring", "plan", true ],
        [ "Summer 2028", 202830, 3, "summer", "plan", false ],
        [ "Fall 2028", 202910, 4, "fall", "plan", false ]
      ]
    )
    expect(result[:timeline].map { |term| term.values_at(:when, :estimated) }.first(4))
      .to eq([ [ "past", false ], [ "past", false ], [ "current", false ], [ "registering", false ] ])
  end

  it "lists a summer class the student took, and moves a later row into the room it leaves" do
    rows = [
      course("WDGT 1100", 1, "fall", status: "done", term: "Fall 2025"),
      course("WDGT 1200", 1, "spring", status: "done", term: "Spring 2026"),
      course("WDGT 2100", 2, "fall", status: "done", term: "Summer 2026"),
      course("WDGT 2200", 2, "spring", status: "in_progress", term: "Fall 2026"),
      course("WDGT 3100", 3, "fall")
    ]

    result = estimate(rows)

    expect(placed(result)).to include("WDGT 2100" => [ "Summer 2026", "taken" ], "WDGT 2200" => [ "Fall 2026", "taken" ],
                                      "WDGT 3100" => [ "Spring 2027", "load" ])
    expect(timeline(result)).to eq(
      [ [ "Fall 2025", "taken", false ], [ "Spring 2026", "taken", false ], [ "Summer 2026", "taken", false ],
        [ "Fall 2026", "taken", false ], [ "Spring 2027", "estimate", false ] ]
    )
    expect(result[:timeline][2]).to include(season: "summer", year: 1, estimated: false)
    expect(result[:expected_end]).to eq(term: "Spring 2027", estimated: true, plan_end: "Fall 2027")
  end

  it "keeps the plan's gap after a co-op taken a term early, and gives a co-op term no classes" do
    rows = [
      course("WDGT 1100", 1, "fall", status: "done", term: "Fall 2025"),
      course("WDGT 1200", 1, "spring", status: "in_progress", term: "Fall 2026"),
      course("COOP 3500", 2, "fall", status: "done", term: "Spring 2026", credits: 0),
      course("WDGT 2200", 2, "spring"),
      course("COOP 4500", 3, "fall", credits: 0),
      course("WDGT 3200", 3, "spring")
    ]

    result = estimate(rows)

    expect(placed(result)).to include("COOP 3500" => [ "Spring 2026", "taken" ], "COOP 4500" => [ "Spring 2027", "co_op" ],
                                      "WDGT 2200" => [ "Fall 2027", "co_op" ], "WDGT 3200" => [ "Spring 2028", nil ])
    expect(timeline(result)).to eq(
      [ [ "Fall 2025", "taken", false ], [ "Spring 2026", "taken", true ], [ "Fall 2026", "taken", false ],
        [ "Spring 2027", "estimate", true ], [ "Fall 2027", "estimate", false ], [ "Spring 2028", "plan", false ] ]
    )
    expect(result[:expected_end]).to include(term: "Spring 2028", plan_end: "Spring 2028")
  end

  it "puts a course taken out of order in its term, and a skipped course first" do
    rows = [
      course("WDGT 1100", 1, "fall"),
      course("WDGT 1200", 1, "spring", status: "done", term: "Fall 2025"),
      course("WDGT 2100", 2, "fall")
    ]

    result = estimate(rows, current_term_uid: 202620)

    # Summer 2026 has no class semester in the plan, so the first term with
    # classes is Fall 2026.
    expect(placed(result)).to eq("WDGT 1100" => [ "Fall 2026", "behind" ], "WDGT 1200" => [ "Fall 2025", "taken" ],
                                 "WDGT 2100" => [ "Spring 2027", "load" ])
    expect(result[:requirements].pluck(:planned_term, :behind))
      .to eq([ [ "Fall 2025", true ], [ "Spring 2026", false ], [ "Fall 2026", false ] ])
  end

  it "puts a fall-only course in a fall term, and a course with no data anywhere" do
    rows = [
      course("WDGT 2200", 2, "spring", offered: %w[fall]),
      course("WDGT 2201", 2, "spring"),
      course("WDGT 2202", 2, "spring", offered: %w[fall spring])
    ]

    expect(placed(estimate(rows))).to eq("WDGT 2200" => [ "Fall 2027", "offered" ], "WDGT 2201" => [ "Spring 2027", nil ],
                                         "WDGT 2202" => [ "Spring 2027", nil ])
  end

  it "places a course after the term of an open prerequisite, and does not wait for a course outside the plan" do
    trees[[ "WDGT", 2200 ]] = requires("WDGT 1100")
    trees[[ "WDGT", 2201 ]] = requires("GEAR 9000")
    rows = [ course("WDGT 1100", 1, "fall"), course("WDGT 2200", 2, "spring"), course("WDGT 2201", 2, "spring") ]

    expect(placed(estimate(rows))).to eq("WDGT 1100" => [ "Spring 2027", "behind" ], "WDGT 2200" => [ "Fall 2027", "prerequisite" ],
                                         "WDGT 2201" => [ "Spring 2027", nil ])
  end

  it "counts a prerequisite through a course code alias" do
    trees[[ "WDGT", 2200 ]] = requires("WDGT 1000")
    rows = [ course("WDGT 1100", 1, "fall"), course("WDGT 2200", 2, "spring"), course("WDGT 2201", 2, "spring") ]
    entry = AcademicProfiles::PlanTerms.new(start, current_term_uid: current).call({ requirements: rows })
    aliases = { [ "WDGT", 1000 ] => [ [ "WDGT", 1100 ] ], [ "WDGT", 1100 ] => [ [ "WDGT", 1000 ] ] }

    result = described_class.new(start, current_term_uid: current, prerequisites: prerequisites, aliases: aliases).call(entry)

    expect(placed(result)["WDGT 2200"]).to eq([ "Fall 2027", "prerequisite" ])
  end

  it "puts at most 20 credits in a term" do
    rows = (1..6).map { |number| course("WDGT 220#{number}", 2, "spring") }

    result = estimate(rows)

    expect(result[:requirements].count { |row| row[:expected_term] == "Spring 2027" }).to eq(5)
    expect(placed(result)["WDGT 2206"]).to eq([ "Fall 2027", "load" ])
  end

  it "places an elective slot and a choice by their credits, with no prerequisite or offered check" do
    slot = course(nil, 2, "spring", kind: "placeholder", credits: nil).merge(label: "Free Elective")
    choice = course(nil, 2, "spring", kind: "choice").merge(options: [ "WDGT 2300", "WDGT 2400" ])

    result = estimate([ slot, choice ])

    expect(result[:requirements].pluck(:expected_term, :moved)).to eq([ [ "Spring 2027", nil ], [ "Spring 2027", nil ] ])
  end

  it "stops after a bounded number of terms, and gives a row in a prerequisite cycle no term" do
    trees[[ "WDGT", 2200 ]] = requires("WDGT 2201")
    trees[[ "WDGT", 2201 ]] = requires("WDGT 2200")
    rows = [ course("WDGT 2200", 2, "spring"), course("WDGT 2201", 2, "spring"), course("WDGT 2202", 2, "spring") ]

    result = estimate(rows)

    expect(result[:requirements].pluck(:code, :expected_term, :moved))
      .to eq([ [ "WDGT 2200", nil, "prerequisite" ], [ "WDGT 2201", nil, "prerequisite" ], [ "WDGT 2202", "Spring 2027", nil ] ])
    expect(result[:timeline].pluck(:term)).to eq([ "Spring 2027" ])
    expect(described_class::Rules::EXTRA_TERMS).to eq(9)
  end

  it "keeps the planned term and behind of #990 on each row" do
    rows = [ course("WDGT 1100", 1, "fall"), course("WDGT 2200", 2, "spring") ]

    expect(estimate(rows)[:requirements].pluck(:planned_term, :planned_term_uid, :behind))
      .to eq([ [ "Fall 2025", 202610, true ], [ "Spring 2027", 202720, false ] ])
  end

  it "gives a term before the start of the program no plan year" do
    rows = [ course("WDGT 1100", 1, "fall", status: "done", term: "Spring 2025") ]

    expect(estimate(rows)[:timeline].sole).to include(term: "Spring 2025", year: nil, basis: "taken")
  end
end
