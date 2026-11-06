# frozen_string_literal: true

module Dashboard
  # Draws AcademicProfiles::CurriculumGraph as an SVG on the server: one
  # column for each semester, one box for each plan row, and a curve from each
  # prerequisite to the course that needs it (#449). Each box with a course
  # links to the same page with that course as the focus (#448).
  module CurriculumHelper
    NODE_WIDTH = 176
    NODE_HEIGHT = 52
    COLUMN_GAP = 48
    ROW_GAP = 14
    HEADER_HEIGHT = 32
    PADDING = 8
    SAME_COLUMN_BEND = 32

    STATUS_LABELS = { "done" => "Done", "in_progress" => "In progress", "open" => "Open", "unchecked" => "Not checked" }.freeze
    STATUS_BADGES = { "done" => "m3-badge-tertiary", "in_progress" => "m3-badge-secondary", "open" => "m3-badge-primary",
                      "unchecked" => "m3-badge-secondary" }.freeze
    STATUS_FILLS = {
      "done"        => [ "fill-tertiary-container", "stroke-tertiary" ],
      "in_progress" => [ "fill-secondary-container", "stroke-secondary" ],
      "open"        => [ "fill-surface-container-lowest", "stroke-outline" ],
      "unchecked"   => [ "fill-surface-container", "stroke-outline-variant" ]
    }.freeze

    # The size of the drawing and the top left corner of each node, by id.
    def curriculum_layout(graph)
      positions = {}
      graph[:semesters].each_with_index do |semester, column|
        semester[:nodes].each_with_index do |node, row|
          positions[node[:id]] = { x: PADDING + (column * (NODE_WIDTH + COLUMN_GAP)),
                                   y: HEADER_HEIGHT + (row * (NODE_HEIGHT + ROW_GAP)) }
        end
      end
      columns = graph[:semesters].size
      rows = graph[:semesters].map { |semester| semester[:nodes].size }.max || 0

      {
        positions: positions,
        # The right side has room for an edge between two nodes of the last
        # column, which bends out to the right.
        width:     PADDING + SAME_COLUMN_BEND + (columns * NODE_WIDTH) + ([ columns - 1, 0 ].max * COLUMN_GAP),
        height:    HEADER_HEIGHT + (rows * NODE_HEIGHT) + ([ rows - 1, 0 ].max * ROW_GAP) + PADDING
      }
    end

    def curriculum_column_x(index) = PADDING + (index * (NODE_WIDTH + COLUMN_GAP))

    # A curve from the right side of one node to the left side of the next.
    # Two nodes in one column get a curve that bends out to the right.
    # An edge back to an earlier column (a plan that lists a course before its
    # prerequisite) gets the plain curve.
    def curriculum_edge_path(from, to)
      y1 = from[:y] + (NODE_HEIGHT / 2)
      y2 = to[:y] + (NODE_HEIGHT / 2)
      if from[:x] == to[:x]
        x = from[:x] + NODE_WIDTH
        return "M#{x},#{y1} C#{x + SAME_COLUMN_BEND - 4},#{y1} #{x + SAME_COLUMN_BEND - 4},#{y2} #{x},#{y2}"
      end

      x1 = from[:x] + NODE_WIDTH
      x2 = to[:x]
      return curriculum_long_edge_path(x1, y1, x2, y2, curriculum_gap_y(to, y1)) if x2 - x1 > COLUMN_GAP

      middle = (x1 + x2) / 2
      "M#{x1},#{y1} C#{middle},#{y1} #{middle},#{y2} #{x2},#{y2}"
    end

    # The row gap next to a target node that an edge from y runs in: the gap
    # above it when that is closer, else the gap below. The first row has the
    # semester labels above it, so its edges use the gap below.
    def curriculum_gap_y(to, from_y)
      above = to[:y] - (ROW_GAP / 2)
      below = to[:y] + NODE_HEIGHT + (ROW_GAP / 2)
      to[:y] > HEADER_HEIGHT && (from_y - above).abs < (from_y - below).abs ? above : below
    end

    # An edge that skips a column runs in a gap between two rows, so it does
    # not cross the nodes between.
    def curriculum_long_edge_path(x1, y1, x2, y2, gap_y)
      turn = COLUMN_GAP / 2
      "M#{x1},#{y1} C#{x1 + turn},#{y1} #{x1 + turn},#{gap_y} #{x1 + COLUMN_GAP},#{gap_y} " \
        "L#{x2 - COLUMN_GAP},#{gap_y} C#{x2 - turn},#{gap_y} #{x2 - turn},#{y2} #{x2},#{y2}"
    end

    # The course a node links to: its own code, or the course that met a
    # choice or an elective slot. Nil for an open choice or slot.
    def curriculum_node_course(node) = node[:code] || node[:course]

    # The two lines of text in a node.
    def curriculum_node_lines(node)
      case node[:kind]
      when "course"
        [ node[:code], node[:label] ]
      when "choice"
        [ node[:course] || "Choose one", node[:options].join(" or ") ]
      else
        [ node[:label], node[:course] || node[:elective_list] || "Any course" ]
      end
    end

    # The status to show for a node. An open slot that WIT Calendar cannot
    # check, such as a free elective, is "unchecked".
    def curriculum_node_status(node)
      node[:status] == "open" && !node[:checkable] ? "unchecked" : node[:status]
    end

    # The text a screen reader says for a node.
    def curriculum_node_name(node)
      [ *curriculum_node_lines(node).compact, curriculum_status_label(curriculum_node_status(node)) ].join(", ")
    end

    def curriculum_status_label(status) = STATUS_LABELS.fetch(status, status.to_s.humanize)
    def curriculum_status_badge(status) = STATUS_BADGES.fetch(status, "m3-badge-primary")
    # The fill of a node by status. A focused node gets the primary outline.
    def curriculum_node_fill(status, focused: false)
      fill, stroke = STATUS_FILLS.fetch(status, STATUS_FILLS["open"])
      "#{fill} #{focused ? 'stroke-primary' : stroke}"
    end

    # The ids of the nodes that stand for the focus course.
    def curriculum_focus_ids(graph)
      code = graph.dig(:focus, :code)
      return [] if code.nil?

      graph[:semesters].flat_map { |semester| semester[:nodes] }
                       .select { |node| [ node[:code], node[:course], *node[:options] ].include?(code) }
                       .pluck(:id)
    end

    # This page with another focus course. The program and plan stay.
    def curriculum_focus_path(code)
      dashboard_curriculum_path(request.query_parameters.slice("program", "plan").merge(focus: code.to_s.delete(" ")))
    end
  end
end
