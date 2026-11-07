# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::PrerequisiteGraphHelper, type: :helper do
  let(:width)  { described_class::GRAPH_NODE_WIDTH }
  let(:height) { described_class::GRAPH_NODE_HEIGHT }
  let(:column) { width + described_class::GRAPH_COLUMN_GAP }
  let(:row)    { height + described_class::GRAPH_ROW_GAP }

  it "puts each column side by side, centered on the tallest column, with a curve for each edge" do
    first  = create(:catalog_course, subject_code: "COMP", course_number: 1000)
    second = create(:catalog_course, subject_code: "COMP", course_number: 1100)
    course = create(:catalog_course, subject_code: "COMP", course_number: 2000, prerequisites: {
      "type" => "or", "operands" => [ first, second ].map { |item| { "type" => "course", "subject_code" => "COMP", "course_number" => item.course_number } }
    })

    layout = helper.prerequisite_graph_layout(Catalog::PrerequisiteGraph.new(course))
    boxes  = layout.boxes.to_h { |box| [ box.node.code, [ box.x, box.y ] ] }

    expect([ layout.width, layout.height ]).to eq([ column + width, row + height ])
    expect(boxes).to eq("COMP 1000" => [ 0, 0 ], "COMP 1100" => [ 0, row ], "COMP 2000" => [ column, row / 2 ])
    expect(layout.lines.map(&:required)).to eq([ false, false ])
    expect(layout.lines.first.path).to start_with("M#{width} #{height / 2} C").and end_with("#{column} #{(row / 2) + (height / 2)}")
  end
end
