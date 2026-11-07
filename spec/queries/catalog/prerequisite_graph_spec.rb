# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::PrerequisiteGraph do
  def ref(course) = { "type" => "course", "subject_code" => course.subject_code, "course_number" => course.course_number }
  def all_of(*nodes) = { "type" => "and", "operands" => nodes }
  def any_of(*nodes) = { "type" => "or", "operands" => nodes }

  def layers(graph) = graph.nodes.to_h { |node| [ node.code, node.layer ] }
  def edges(graph) = graph.edges.to_h { |edge| [ [ edge.from, edge.to ], edge.required ] }

  let(:intro)    { create(:catalog_course, subject_code: "COMP", course_number: 1000) }
  let(:calculus) { create(:catalog_course, subject_code: "MATH", course_number: 1750) }
  let(:middle)   { create(:catalog_course, subject_code: "COMP", course_number: 2000, prerequisites: ref(intro)) }

  it "puts each prerequisite on the layer of its longest chain to the course" do
    course = create(:catalog_course, subject_code: "COMP", course_number: 3000, prerequisites: all_of(ref(middle), ref(intro)))

    graph = described_class.new(course)

    expect(layers(graph)).to eq("COMP 3000" => 0, "COMP 2000" => -1, "COMP 1000" => -2)
    expect(edges(graph)).to eq([ "COMP 2000", "COMP 3000" ] => true, [ "COMP 1000", "COMP 2000" ] => true,
                               [ "COMP 1000", "COMP 3000" ] => true)
    expect(graph.columns.map { |column| column.map(&:code) }).to eq([ [ "COMP 1000" ], [ "COMP 2000" ], [ "COMP 3000" ] ])
  end

  it "marks a course in an or group as one option, and a lone course as required" do
    test = { "type" => "test", "name" => "Math placement", "score" => "50" }
    course = create(:catalog_course, prerequisites: all_of(any_of(ref(intro), ref(calculus)), any_of(ref(middle)), any_of(ref(create(:catalog_course, subject_code: "ENGL", course_number: 1100)), test)))

    into_course = edges(described_class.new(course)).select { |(_, to), _| to == course.code }.transform_keys(&:first)

    expect(into_course).to eq("COMP 1000" => false, "MATH 1750" => false, "COMP 2000" => true, "ENGL 1100" => false)
  end

  it "shows a course that WIT Calendar does not know, without walking past it" do
    course = create(:catalog_course, prerequisites: { "type" => "course", "subject_code" => "COMP", "course_number" => 128 })

    node = described_class.new(course).nodes.find { |item| item.code == "COMP 128" }

    expect(node).to have_attributes(linked: false, title: nil, layer: -1)
  end

  it "puts the courses it unlocks on layer 1, with the edge type from their own trees" do
    course = create(:catalog_course, subject_code: "COMP", course_number: 2500)
    required = create(:catalog_course, subject_code: "COMP", course_number: 3500, prerequisites: ref(course))
    choice   = create(:catalog_course, subject_code: "COMP", course_number: 3600, prerequisites: any_of(ref(course), ref(intro)))
    [ required, choice ].each { |unlocked| create(:course_prerequisite, catalog_course: unlocked, required_catalog_course: course) }

    graph = described_class.new(course)

    expect(layers(graph)).to eq("COMP 2500" => 0, "COMP 3500" => 1, "COMP 3600" => 1)
    expect(edges(graph)).to eq([ "COMP 2500", "COMP 3500" ] => true, [ "COMP 2500", "COMP 3600" ] => false)
  end

  it "shows only the first unlocked courses and counts the rest" do
    stub_const("#{described_class}::MAX_UNLOCKS", 2)
    course = create(:catalog_course)
    create_list(:course_prerequisite, 3, required_catalog_course: course)

    graph = described_class.new(course)

    expect(graph.nodes.count { |node| node.layer == 1 }).to eq(2)
    expect(graph.hidden_unlocks).to eq(1)
  end

  it "stops the walk at the depth limit and says so" do
    stub_const("#{described_class}::MAX_DEPTH", 1)
    course = create(:catalog_course, prerequisites: ref(middle))

    graph = described_class.new(course)

    expect(graph.nodes.map(&:code)).not_to include("COMP 1000")
    expect(graph).to be_truncated
  end

  it "stops at the course limit and says so" do
    stub_const("#{described_class}::MAX_PREREQUISITES", 1)
    course = create(:catalog_course, prerequisites: all_of(ref(intro), ref(calculus)))

    graph = described_class.new(course)

    expect(graph.nodes.size).to eq(2)
    expect(graph.edges.size).to eq(1)
    expect(graph).to be_truncated
  end

  it "ends and keeps every line left to right when Banner's data has a cycle" do
    first  = create(:catalog_course, subject_code: "COMP", course_number: 4100)
    second = create(:catalog_course, subject_code: "COMP", course_number: 4200, prerequisites: ref(first))
    first.update!(prerequisites: ref(second))

    graph = described_class.new(second)
    layer = layers(graph)

    expect(graph.edges).to all(satisfy { |edge| layer[edge.from] < layer[edge.to] })
  end

  it "is empty for a course with no prerequisites that unlocks nothing" do
    graph = described_class.new(create(:catalog_course))

    expect(graph).to be_empty
    expect(graph).not_to be_truncated
  end

  it "orders a column so its courses sit next to the courses they lead to" do
    a_first  = create(:catalog_course, subject_code: "AAAA", course_number: 1000)
    z_first  = create(:catalog_course, subject_code: "ZZZZ", course_number: 1000)
    a_second = create(:catalog_course, subject_code: "AAAA", course_number: 2000, prerequisites: ref(z_first))
    z_second = create(:catalog_course, subject_code: "ZZZZ", course_number: 2000, prerequisites: ref(a_first))
    course   = create(:catalog_course, prerequisites: all_of(ref(a_second), ref(z_second)))

    columns = described_class.new(course).columns.map { |column| column.map(&:code) }

    expect(columns.first(2)).to eq([ [ "ZZZZ 1000", "AAAA 1000" ], [ "AAAA 2000", "ZZZZ 2000" ] ])
  end
end
