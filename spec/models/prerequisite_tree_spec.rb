# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrerequisiteTree do
  let(:math) { { "type" => "course", "subject_code" => "math", "course_number" => "1750" } }
  let(:comp) { { "type" => "course", "subject_code" => "COMP", "course_number" => 1000, "min_grade" => "C" } }
  let(:test_node) { { "type" => "test", "name" => "WIT Math Assessment", "score" => "1500" } }
  let(:tree) { described_class.new("type" => "and", "operands" => [ math, { "type" => "or", "operands" => [ comp, test_node ] } ]) }

  it "lists the course nodes and their codes" do
    expect(tree.courses).to eq([ math, comp ])
    expect(tree.codes).to eq([ [ "MATH", 1750 ], [ "COMP", 1000 ] ])
  end

  it "marks a course under an or with another choice as not required" do
    expect(tree.requirements).to eq([ [ "MATH", 1750, true ], [ "COMP", 1000, false ] ])
  end

  it "replaces each course node and keeps the rest" do
    mapped = tree.map_courses { |node| node.merge("seen" => true) }

    expect(described_class.new(mapped).courses).to all(include("seen" => true))
    expect(mapped.dig("operands", 1, "operands", 1)).to eq(test_node)
  end

  it "folds from the leaves up with the depth of each node" do
    text = tree.fold do |node, parts, depth|
      next parts.join(" #{node['type']} ").then { |joined| depth.zero? ? joined : "(#{joined})" } if tree.group?(node)

      node["name"] || node["subject_code"]
    end

    expect(text).to eq("math and (COMP or WIT Math Assessment)")
  end

  it "is empty for a course with no prerequisites" do
    tree = described_class.new(nil)

    expect([ tree.courses, tree.requirements, tree.map_courses { |node| node }, tree.fold { nil } ]).to eq([ [], [], nil, nil ])
  end
end
