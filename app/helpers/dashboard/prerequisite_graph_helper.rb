# frozen_string_literal: true

module Dashboard
  # Places the nodes of a Catalog::PrerequisiteGraph on the course page
  # (#448). Each column of the graph is one column of boxes, centered on the
  # tallest column. The lines are curves from the right side of a
  # prerequisite to the left side of the course it leads to.
  module PrerequisiteGraphHelper
    GRAPH_NODE_WIDTH  = 136
    GRAPH_NODE_HEIGHT = 52
    GRAPH_COLUMN_GAP  = 40
    GRAPH_ROW_GAP     = 12

    GraphBox  = Data.define(:node, :x, :y)
    GraphLine = Data.define(:path, :required)
    GraphLayout = Data.define(:width, :height, :boxes, :lines)

    def prerequisite_graph_layout(graph)
      columns = graph.columns
      tallest = columns.map(&:size).max
      height  = (tallest * (GRAPH_NODE_HEIGHT + GRAPH_ROW_GAP)) - GRAPH_ROW_GAP
      width   = (columns.size * (GRAPH_NODE_WIDTH + GRAPH_COLUMN_GAP)) - GRAPH_COLUMN_GAP

      boxes = columns.each_with_index.flat_map do |column, index|
        x   = index * (GRAPH_NODE_WIDTH + GRAPH_COLUMN_GAP)
        top = (height - ((column.size * (GRAPH_NODE_HEIGHT + GRAPH_ROW_GAP)) - GRAPH_ROW_GAP)) / 2
        column.each_with_index.map { |node, row| GraphBox.new(node: node, x: x, y: top + (row * (GRAPH_NODE_HEIGHT + GRAPH_ROW_GAP))) }
      end

      by_code = boxes.index_by { |box| box.node.code }
      lines = graph.edges.filter_map do |edge|
        from = by_code[edge.from]
        to   = by_code[edge.to]
        next unless from && to

        GraphLine.new(path: prerequisite_graph_curve(from, to), required: edge.required)
      end

      GraphLayout.new(width: width, height: height, boxes: boxes, lines: lines)
    end

    private

    def prerequisite_graph_curve(from, to)
      start_x = from.x + GRAPH_NODE_WIDTH
      start_y = from.y + (GRAPH_NODE_HEIGHT / 2)
      end_x   = to.x
      end_y   = to.y + (GRAPH_NODE_HEIGHT / 2)
      bend    = (end_x - start_x) / 2

      "M#{start_x} #{start_y} C#{start_x + bend} #{start_y}, #{end_x - bend} #{end_y}, #{end_x} #{end_y}"
    end
  end
end
