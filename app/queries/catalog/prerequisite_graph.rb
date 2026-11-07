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

    # The graph reads only these columns. A full row carries the embedding.
    SUMMARY_COLUMNS = %i[id subject_code course_number title prerequisites].freeze

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

    # Breadth first, in memory. ancestors loads every course the walk can
    # reach, so the walk itself sends no query.
    def walk_prerequisites
      known    = ancestors
      frontier = [ course ]
      visited  = Set[course.code]

      MAX_DEPTH.times do
        refs = frontier.to_h { |item| [ item, requirement_refs(item.prerequisites) ] }
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
      drop_cycle_edges

      before = prerequisites_of
      order  = []
      seen   = Set.new
      visit  = lambda do |code|
        next unless seen.add?(code)

        before[code].each { |prerequisite| visit.call(prerequisite) }
        order << code
      end
      visit.call(course.code)

      # The reverse of a depth-first finish order visits a course before its
      # prerequisites, so each depth is final before it moves left.
      depth = { course.code => 0 }
      order.reverse_each do |code|
        next unless depth.key?(code)

        before[code].each { |prerequisite| depth[prerequisite] = [ depth.fetch(prerequisite, 0), depth[code] + 1 ].max }
      end

      @nodes.transform_values! { |node| node.with(layer: -depth.fetch(node.code, 1)) }
      @nodes[course.code] = @nodes[course.code].with(layer: 0)
    end

    # Banner's data can have a cycle, such as two courses that list each
    # other. A depth-first walk from the course finds the edges that close a
    # cycle. Only those edges go. Every other edge stays.
    def drop_cycle_edges
      before   = prerequisites_of
      on_path  = Set.new
      finished = Set.new
      visit    = lambda do |code|
        on_path << code
        before[code].each do |prerequisite|
          if on_path.include?(prerequisite)
            @edges.delete([ prerequisite, code ])
          elsif !finished.include?(prerequisite)
            visit.call(prerequisite)
          end
        end
        on_path.delete(code)
        finished << code
      end
      visit.call(course.code)
    end

    # { "COMP 2000" => ["COMP 1050", ...] }: the prerequisites of each course.
    def prerequisites_of
      @edges.each_value.with_object(Hash.new { |hash, key| hash[key] = [] }) { |edge, map| map[edge.to] << edge.from }
    end

    def add_unlocks
      unlocks = course.unlocks.distinct.select(*SUMMARY_COLUMNS).order(:subject_code, :course_number).to_a
      unlocks.reject! { |unlocked| @nodes.key?(unlocked.code) }
      @hidden_unlocks = [ unlocks.size - MAX_UNLOCKS, 0 ].max

      unlocks.first(MAX_UNLOCKS).each do |unlocked|
        add_node(unlocked, unlocked.code, layer: 1)
        refs = requirement_refs(unlocked.prerequisites).select { |subject, number, _| subject == course.subject_code && number == course.course_number }
        add_edge(course.code, unlocked.code, refs.empty? || refs.any?(&:last))
      end
    end

    # A last guard: an edge that still points right to left is not drawn.
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

    # Every CatalogCourse that the prerequisite trees name, up to MAX_DEPTH
    # levels from the course, keyed by [subject_code, course_number]. One
    # recursive query reads the same trees that requirement_refs reads, so a
    # course with no course_prerequisites row is still found.
    def ancestors
      ids = CatalogCourse.connection.select_values(CatalogCourse.sanitize_sql_array([ <<~SQL.squish, { root: course.id, max_depth: MAX_DEPTH } ]))
        WITH RECURSIVE walk(id, depth) AS (
          SELECT id, 0 FROM catalog_courses WHERE id = :root
          UNION
          SELECT required.id, walk.depth + 1
          FROM walk
          JOIN catalog_courses parent ON parent.id = walk.id
          CROSS JOIN LATERAL jsonb_path_query(parent.prerequisites, 'lax $.** ? (@.type == "course")') AS leaf
          JOIN catalog_courses required ON required.subject_code = upper(leaf ->> 'subject_code')
                                       AND required.course_number = (leaf ->> 'course_number')::integer
          WHERE walk.depth < :max_depth
        )
        SELECT DISTINCT id FROM walk
      SQL

      CatalogCourse.select(*SUMMARY_COLUMNS).where(id: ids).index_by { |found| [ found.subject_code, found.course_number ] }
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
