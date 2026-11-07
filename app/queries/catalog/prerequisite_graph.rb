# frozen_string_literal: true

module Catalog
  # The prerequisite graph around one catalog course (#448): every course a
  # student takes before it, and the courses it is a prerequisite for.
  #
  # Each node has a layer. The course is layer 0. A prerequisite is on a
  # negative layer, as far left as its longest chain to the course, so every
  # edge points from left to right. The courses it unlocks are on layer 1.
  #
  # An edge is required when the student must take that course. It is not
  # required when the course is one choice in an "or" group.
  #
  # The walk stops after MAX_DEPTH levels and MAX_PREREQUISITES courses.
  # Only the first MAX_UNLOCKS unlocked courses show. truncated? and
  # hidden_unlocks tell the page what it left out.
  class PrerequisiteGraph
    MAX_DEPTH         = 6
    MAX_PREREQUISITES = 40
    MAX_UNLOCKS       = 24

    # code is "COMP 2000". linked is true when WIT Calendar has the course.
    Node = Data.define(:code, :title, :linked, :layer) do
      def root? = layer.zero?
    end

    # from is a prerequisite of to. Both are codes.
    Edge = Data.define(:from, :to, :required)

    attr_reader :course

    def initialize(catalog_course)
      @course = catalog_course
    end

    def nodes
      build
      @nodes.values
    end

    def edges
      build
      @edges.values
    end

    # True when the walk left out a prerequisite.
    def truncated?
      build
      @truncated
    end

    # How many unlocked courses the graph does not show.
    def hidden_unlocks
      build
      @hidden_unlocks
    end

    # True when the course has no prerequisite and unlocks nothing.
    def empty?
      nodes.size <= 1
    end

    # The nodes in columns, from the first prerequisites to the unlocked
    # courses. Each column is in an order that keeps lines from crossing.
    def columns
      @columns ||= begin
        by_layer = nodes.group_by(&:layer).transform_values { |list| list.sort_by(&:code) }
        order_prerequisite_layers(by_layer)
        by_layer.sort_by(&:first).map(&:last)
      end
    end

    private

    def build
      return if @built

      @built          = true
      @nodes          = {}
      @edges          = {}
      @truncated      = false
      @hidden_unlocks = 0
      @layers         = { course.code => 0 }

      add_node(course, course.code)
      walk_prerequisites
      assign_prerequisite_layers
      add_unlocks
      drop_backward_edges
    end

    # Breadth first, one query for each level.
    def walk_prerequisites
      frontier = [ course ]
      visited  = Set[course.code]

      MAX_DEPTH.times do
        refs = frontier.to_h { |item| [ item, requirement_refs(item.prerequisites) ] }
        known = find_courses(refs.values.flatten(1).map { |subject, number, _| [ subject, number ] })
        frontier = []

        refs.each do |item, list|
          list.each do |subject, number, required|
            code = "#{subject} #{number}"
            unless @nodes.key?(code)
              if @nodes.size - 1 >= MAX_PREREQUISITES
                @truncated = true
                next
              end
              add_node(known[[ subject, number ]], code)
            end
            add_edge(code, item.code, required)

            found = known[[ subject, number ]]
            frontier << found if found && visited.add?(code)
          end
        end

        return if frontier.empty?
      end

      @truncated ||= frontier.any? { |item| requirement_refs(item.prerequisites).any? }
    end

    # Each prerequisite goes as far left as its longest chain to the course.
    def assign_prerequisite_layers
      before = Hash.new { |hash, key| hash[key] = [] }
      @edges.each_value { |edge| before[edge.to] << edge.from }

      depth = { course.code => 0 }
      queue = [ course.code ]
      # A depth only grows, and it stops below the number of nodes, so the
      # loop ends even when Banner's data has a cycle.
      while (code = queue.shift)
        before[code].each do |prerequisite|
          next if depth.fetch(prerequisite, -1) >= depth[code] + 1 || depth[code] + 1 >= @nodes.size

          depth[prerequisite] = depth[code] + 1
          queue << prerequisite
        end
      end

      @nodes.transform_values! { |node| node.with(layer: -depth.fetch(node.code, 1)) }
      @nodes[course.code] = @nodes[course.code].with(layer: 0)
    end

    def add_unlocks
      unlocks = course.unlocks.distinct.order(:subject_code, :course_number).to_a
      unlocks.reject! { |unlocked| @nodes.key?(unlocked.code) }
      @hidden_unlocks = [ unlocks.size - MAX_UNLOCKS, 0 ].max

      unlocks.first(MAX_UNLOCKS).each do |unlocked|
        add_node(unlocked, unlocked.code, layer: 1)
        ref = requirement_refs(unlocked.prerequisites).find { |subject, number, _| subject == course.subject_code && number == course.course_number }
        add_edge(course.code, unlocked.code, ref ? ref.last : true)
      end
    end

    # A cycle in Banner's data can leave an edge that points right to left.
    def drop_backward_edges
      @edges.select! { |_, edge| @nodes[edge.from].layer < @nodes[edge.to].layer }
    end

    def add_node(catalog_course, code, layer: 0)
      @nodes[code] = Node.new(code: code, title: catalog_course&.title, linked: catalog_course.present?, layer: layer)
    end

    # A course named twice keeps the edge required when either name is.
    def add_edge(from, to, required)
      key = [ from, to ]
      @edges[key] = Edge.new(from: from, to: to, required: required || @edges[key]&.required || false)
    end

    # [[subject_code, course_number, required], ...] for every course the tree
    # names. A test is not a course, but it counts as a choice in an "or".
    def requirement_refs(node, required: true)
      return [] if node.nil?

      case node["type"]
      when "course"
        [ [ node["subject_code"].to_s.upcase, node["course_number"].to_i, required ] ]
      when "and"
        Array(node["operands"]).flat_map { |operand| requirement_refs(operand, required: required) }
      when "or"
        operands = Array(node["operands"])
        operands.flat_map { |operand| requirement_refs(operand, required: required && operands.size == 1) }
      else
        []
      end
    end

    def find_courses(pairs)
      pairs = pairs.uniq
      return {} if pairs.empty?

      conditions = pairs.map { "(subject_code = ? AND course_number = ?)" }.join(" OR ")
      CatalogCourse.where(conditions, *pairs.flatten).index_by { |found| [ found.subject_code, found.course_number ] }
    end

    # Moving left from the course, sort each column by the mean position of
    # the courses it leads to in the column to its right.
    def order_prerequisite_layers(by_layer)
      after = Hash.new { |hash, key| hash[key] = [] }
      edges.each { |edge| after[edge.from] << edge.to }

      position = {}
      by_layer.keys.reject(&:positive?).sort.reverse_each do |layer|
        list = by_layer[layer]
        unless layer.zero?
          list.sort_by!.with_index do |node, index|
            targets = after[node.code].filter_map { |code| position[code] }
            [ targets.empty? ? Float::INFINITY : targets.sum.fdiv(targets.size), index ]
          end
        end
        list.each_with_index { |node, index| position[node.code] = index.fdiv([ list.size - 1, 1 ].max) }
      end
    end
  end
end
