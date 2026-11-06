# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::CurriculumHelper, type: :helper do
  let(:width) { described_class::NODE_WIDTH }
  let(:gap) { described_class::COLUMN_GAP }

  def node(column, row)
    { x: 8 + (column * (width + gap)), y: 32 + (row * 66) }
  end

  describe "#curriculum_edge_path" do
    it "draws a plain curve between two columns next to each other" do
      expect(helper.curriculum_edge_path(node(0, 0), node(1, 1))).to eq("M184,58 C208,58 208,124 232,124")
    end

    it "bends out to the right between two nodes in one column" do
      expect(helper.curriculum_edge_path(node(0, 0), node(0, 1))).to eq("M184,58 C212,58 212,124 184,124")
    end

    it "runs an edge that skips a column in the gap below a first-row target" do
      expect(helper.curriculum_edge_path(node(0, 1), node(2, 0))).to include("L408,91 ")
    end

    it "runs an edge in the gap above a lower target when that gap is closer" do
      expect(helper.curriculum_edge_path(node(0, 0), node(2, 2))).to include("L408,157 ")
    end
  end

  describe "#curriculum_node_lines" do
    it "names a course, a choice, and an elective slot" do
      expect(helper.curriculum_node_lines({ kind: "course", code: "WDGT 1000", label: "Intro" })).to eq([ "WDGT 1000", "Intro" ])
      expect(helper.curriculum_node_lines({ kind: "choice", options: [ "A 1", "B 2" ] })).to eq([ "Choose one", "A 1 or B 2" ])
      expect(helper.curriculum_node_lines({ kind: "placeholder", label: "Free Elective", options: [] })).to eq([ "Free Elective", "Any course" ])
      expect(helper.curriculum_node_lines({ kind: "placeholder", label: "Widget Elective", elective_list: "Widget Electives", options: [] }))
        .to eq([ "Widget Elective", "Widget Electives" ])
    end
  end

  describe "#curriculum_node_status" do
    it "marks an open slot that cannot be checked as unchecked" do
      expect(helper.curriculum_node_status({ status: "open", checkable: false })).to eq("unchecked")
      expect(helper.curriculum_node_status({ status: "open", checkable: true })).to eq("open")
      expect(helper.curriculum_node_status({ status: "done", checkable: true })).to eq("done")
    end
  end
end
