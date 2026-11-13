# frozen_string_literal: true

module AcademicProfiles
  # Where the extra courses of a planned minor fit in the plans of the active
  # programs (#998). ProgramOverlap calls it for a planned program with no
  # plan of study, and adds slots, unplaced, and expected_end_with_minor to
  # its overlap. It is an estimate for planning: it does not check that a
  # course is offered in the term of a slot. See docs/degree-requirements.md.
  #
  # Each slot takes one extra course, and each extra course uses one slot.
  # The narrow slots (a program elective or an HSS slot) take courses first,
  # in term order, then the free electives in term order, so a free elective
  # is not used where a narrow slot fits. The assignment is a maximum
  # matching: a later slot can move a course that an earlier slot took to
  # another slot, so the most courses get a slot.
  class MinorFit
    # The most courses that one slot lists.
    MAX_COURSES = 10
    # One more term for each this many courses with no slot.
    COURSES_PER_TERM = 4

    # An open elective slot of an active program. rule is the
    # ElectiveListRule of its list. category is the HSS category that an HSS
    # slot stands for, or nil.
    Slot = Data.define(:label, :term, :term_uid, :rule, :category)

    # The extra courses of one minor list. courses: the keys of the list
    # courses that can be extra, in list order (empty for a list of subjects
    # or of any course). subjects and any_course: the rule of such a list.
    # count: how many extra courses the list needs.
    Need = Data.define(:courses, :subjects, :any_course, :count)

    # A course key for HssMatcher#in_category?.
    Course = Data.define(:subject_code, :course_number) do
      def key = [ subject_code, course_number ]
    end

    # slots: the open slots of the active programs. major_end: the
    # expected_end of the major with { term, uid, estimated }, or nil.
    # matcher: the HssMatcher of DegreeProgress.
    def initialize(slots, major_end:, matcher:)
      @slots = slots
      @major_end = major_end
      @matcher = matcher
    end

    # { slots, unplaced, expected_end_with_minor } for the needs of a minor.
    def call(needs)
      needs = needs.select { |need| need.count.positive? }
      extra = needs.sum(&:count)
      placed = place(needs)
      unplaced = extra - placed.size
      {
        slots:                   placed.map { |slot| slot_json(slot, needs) },
        unplaced:                unplaced,
        expected_end_with_minor: end_with(unplaced)
      }
    end

    private

    # The slots that get a course, in term order (no term last), then plan
    # order.
    def place(needs)
      flow = Flow.new
      needs.flat_map(&:courses).uniq.each { |key| flow.add([ :course, key ], [ :course_out, key ], 1) }
      needs.each_with_index do |need, index|
        flow.add([ :need, index ], :sink, need.count)
        if need.courses.any?
          # A course on two lists is one node, so it fills one slot only.
          need.courses.each { |key| flow.add([ :course_out, key ], [ :need, index ], 1) }
        else
          flow.add([ :open, index ], [ :need, index ], need.count)
        end
      end

      ordered = @slots.each_with_index.sort_by { |slot, index| [ slot.rule.any_course? ? 1 : 0, *term_order(slot), index ] }
      placed = ordered.select do |slot, index|
        needs.each_with_index do |need, need_index|
          if need.courses.any?
            need.courses.each { |key| flow.add([ :slot, index ], [ :course, key ], 1) if accepts?(slot, key) }
          elsif open_fits?(slot, need)
            flow.add([ :slot, index ], [ :open, need_index ], 1)
          end
        end
        flow.augment([ :slot, index ])
      end
      placed.sort_by { |slot, index| [ *term_order(slot), index ] }.map(&:first)
    end

    def term_order(slot) = slot.term_uid ? [ 0, slot.term_uid ] : [ 1, 0 ]

    def accepts?(slot, key)
      slot.rule.accepts?(key) && (slot.category.nil? || @matcher.in_category?(slot.category, Course.new(*key)))
    end

    # A list of subjects fits a slot that takes one of its subjects, or that
    # names a course of one of its subjects. A list of any course fits only
    # a free elective.
    def open_fits?(slot, need)
      return slot.rule.any_course? if need.any_course

      need.subjects.any? do |subject|
        (slot.rule.accepts_subject?(subject) || slot.rule.names_subject?(subject)) && (slot.category.nil? || slot.category["subject_codes"].include?(subject))
      end
    end

    def slot_json(slot, needs)
      courses = needs.flat_map(&:courses).uniq.select { |key| accepts?(slot, key) }
      { label: slot.label, planned_term: slot.term, planned_term_uid: slot.term_uid,
        courses: courses.first(MAX_COURSES).map { |key| key.join(" ") } }
    end

    # The major's expected end, or one fall or spring term later for each
    # COURSES_PER_TERM courses with no slot. nil without a major end.
    def end_with(unplaced)
      return nil if @major_end.nil?
      return @major_end.slice(:term, :estimated) if unplaced.zero?

      uid = @major_end[:uid]
      (unplaced / COURSES_PER_TERM.to_f).ceil.times { uid = NextTermCourses.default_term_uid(uid) }
      { term: TermCode.label(uid), estimated: true }
    end

    # A small flow network for the matching: slot -> course -> need -> sink.
    # augment finds one more path from a slot to the sink, and can move the
    # courses of earlier slots. A slot that got a course keeps one.
    class Flow
      def initialize
        @capacity = Hash.new(0)
        @edges = Hash.new { |hash, node| hash[node] = [] }
      end

      def add(from, to, capacity)
        @edges[from] << to unless @edges[from].include?(to)
        @edges[to] << from unless @edges[to].include?(from)
        @capacity[[ from, to ]] += capacity
      end

      def augment(node, seen = Set.new)
        return true if node == :sink

        seen << node
        @edges[node].each do |to|
          next if seen.include?(to) || @capacity[[ node, to ]] <= 0
          next unless augment(to, seen)

          @capacity[[ node, to ]] -= 1
          @capacity[[ to, node ]] += 1
          return true
        end
        false
      end
    end
  end
end
