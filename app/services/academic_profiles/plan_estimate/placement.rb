# frozen_string_literal: true

module AcademicProfiles
  class PlanEstimate
    # Puts each requirement row of one plan in a real term (#1011). It walks
    # the terms one by one from the term after the current term, and gives
    # each term either one co-op or a load of classes. See
    # docs/degree-requirements.md for the rules and a flow chart.
    class Placement
      DONE = %w[done in_progress].freeze
      # When an open row moved later for more than one reason, moved is the
      # first of these.
      REASONS = %w[co_op prerequisite offered load].freeze
      # The value that PrerequisiteCheck counts as passed with a C or better.
      PASSED = [ { outcome: nil } ].freeze

      # The courses that count for the prerequisite check of a row in one
      # term. A course of the plan (waiting) counts when its row is placed
      # before the term, or always with plan: :passed. A course outside the
      # plan counts when the student took it, or always with outside:
      # :passed.
      Counted = Struct.new(:waiting, :placed_at, :term, :taken, :outside, :plan) do
        def fetch(key, default)
          if waiting.include?(key)
            plan == :passed || (placed_at[key] && placed_at[key] < term) ? PASSED : default
          else
            outside == :passed || taken.include?(key) ? PASSED : default
          end
        end
      end

      # rows: the requirement rows with the fields of PlanTerms.
      # prerequisites: answers prerequisites([subject, number]) with a tree
      # or nil (CourseDetails). aliases: each pair with its old and new
      # pairs.
      # taken: the [subject, number] keys of the courses the student did or
      # takes.
      def initialize(rows, current_term_uid:, prerequisites:, aliases:, taken: [])
        @rows = rows
        @taken = taken.to_set
        @current = current_term_uid
        @prerequisites = prerequisites
        @aliases = aliases
        @placed = {}
        @reasons = Hash.new { |hash, index| hash[index] = Set.new }
        @credits = Hash.new(0)
        @counts = Hash.new(0)
        @co_op_terms = Set.new
        @placed_at = {}
      end

      # { index => [ expected_term_uid, moved ] } for each row.
      def call
        place_fixed
        place_open
        @rows.each_index.to_h { |index| [ index, [ @placed[index], moved(index) ] ] }
      end

      private

      # Done and in-progress rows sit in the term the student took them.
      # One in a later term (the student registered) uses that term's load.
      def place_fixed
        fixed.each do |index|
          uid = TermCode.parse(@rows[index][:term])
          next if uid.nil?

          @placed[index] = uid
          next unless uid >= first_term

          if co_op?(index)
            @co_op_terms << uid
          else
            @credits[uid] += Rules.credits(@rows[index])
            @counts[uid] += 1
          end
          keys(index).each { |key| @placed_at[key] = [ @placed_at[key], uid ].compact.min }
        end
      end

      # Each term from the first term on gets one co-op or a load of
      # classes, until every open row has a term or the last term.
      def place_open
        uid = first_term
        while uid <= last_term && open_rows.any? { |index| !@placed.key?(index) }
          if co_op_term?(uid)
            place_co_op(uid)
          elsif class_term?(uid)
            place_classes(uid)
          end
          note_reasons(uid)
          uid = Rules.next_term(uid)
        end
      end

      # The next open co-op goes in a co-op term when its gap after the
      # previous co-op is over and its prerequisites are placed. A term with
      # classes the student registered for gets no co-op.
      def co_op_term?(uid)
        return true if @co_op_terms.include?(uid)
        return false unless co_op_usable?(uid) && @counts[uid].zero?

        index = next_co_op
        earliest = index && co_op_earliest(index)
        earliest.present? && uid >= earliest && !blocked?(index, uid)
      end

      def place_co_op(uid)
        index = next_co_op
        return if @co_op_terms.include?(uid) || index.nil?

        place(index, uid)
        @co_op_terms << uid
      end

      # Open class rows in queue order. A row waits when a prerequisite is
      # not placed before the term, or when the term is a season it is not
      # offered. The term is full when the next row would go over its load,
      # but a term with no row takes one, so the walk moves on.
      def place_classes(uid)
        return if @co_op_terms.include?(uid) && !Rules.classes_in_co_op_term?

        limit = [ load(uid), Rules::MAX_TERM_CREDITS ].min
        queue.each do |index|
          next if @placed.key?(index) || waits?(index, uid)

          credits = Rules.credits(@rows[index])
          break if @counts[uid].positive? && full?(uid, limit, index, credits)

          place(index, uid)
          @credits[uid] += credits
          @counts[uid] += 1
        end
      end

      # Over the load, or at the load for a row of a later plan term. A row
      # with 0 credits of this term (or a behind row) still fits a full term.
      def full?(uid, limit, index, credits)
        @credits[uid] + credits > limit || (@credits[uid] >= limit && @rows[index][:planned_term_uid] > uid)
      end

      def place(index, uid)
        @placed[index] = uid
        keys(index).each { |key| @placed_at[key] = [ @placed_at[key], uid ].compact.min }
      end

      def waits?(index, uid) = blocked?(index, uid) || !offered?(index, uid)

      # The plan's own term always counts as offered, so a plan that puts a
      # fall-only course in a spring term keeps it there.
      def offered?(index, uid)
        uid == @rows[index][:planned_term_uid] || Rules.offered_in?(@rows[index], uid)
      end

      # Why an open row is not in a term, from its planned term until it has
      # a term: in its planned term any reason (reason_in), in a later class
      # term only prerequisite or offered. So a spring-only course that a
      # full term pushes out of spring, and then waits a year, is offered.
      def note_reasons(uid)
        open_rows.each do |index|
          planned = @rows[index][:planned_term_uid]
          next if @placed.key?(index) || planned > uid || planned < first_term

          if planned == uid
            @reasons[index] << reason_in(index, uid)
          elsif later_reason = later_reason_in(index, uid)
            @reasons[index] << later_reason
          end
        end
      end

      def later_reason_in(index, uid)
        return nil if co_op?(index) || @co_op_terms.include?(uid) || !class_term?(uid)
        return "prerequisite" if blocked?(index, uid)

        "offered" unless offered?(index, uid)
      end

      def reason_in(index, uid)
        return blocked?(index, uid) ? "prerequisite" : "co_op" if co_op?(index)
        return "co_op" if @co_op_terms.include?(uid)
        return "prerequisite" if blocked?(index, uid)
        return "offered" unless offered?(index, uid)

        "load"
      end

      # null when the row is in its planned term. A done or in-progress row
      # is "taken". An open row that was behind is "behind". An open row in
      # an earlier term than planned moved for "load" (an earlier term has
      # room), or "co_op" for a co-op. An open row in a later term, or with
      # no term, has the first of its reasons in REASONS order.
      def moved(index)
        row = @rows[index]
        planned = row[:planned_term_uid]
        uid = @placed[index]
        return nil if planned.nil? || uid == planned
        return "taken" if DONE.include?(row[:status])
        return "behind" if planned < first_term
        return co_op?(index) ? "co_op" : "load" if uid && uid < planned

        REASONS.find { |reason| @reasons[index].include?(reason) } || "load"
      end

      # The earliest term of an open co-op: its planned term for the first
      # co-op, else the gap of the plan after the term of the previous
      # co-op. nil while the previous co-op has no term.
      def co_op_earliest(index)
        position = co_op_rows.index(index)
        return [ @rows[index][:planned_term_uid], first_term ].max if position.zero?

        previous = co_op_rows[position - 1]
        return nil unless @placed[previous]

        gap = Rules.co_op_gap(@rows[previous][:planned_term_uid], @rows[index][:planned_term_uid], method(:co_op_usable?))
        [ Rules.advance(@placed[previous], gap, method(:co_op_usable?)), first_term ].max
      end

      def next_co_op = co_op_rows.find { |index| open_rows.include?(index) && !@placed.key?(index) }

      # The co-op rows of the plan, in plan order.
      def co_op_rows
        @co_op_rows ||= plan_rows.select { |index| co_op?(index) }
      end

      # The open class rows: behind rows first, then the other rows in plan
      # order.
      def queue
        @queue ||= open_rows.reject { |index| co_op?(index) }
                            .sort_by { |index| [ @rows[index][:planned_term_uid] < first_term ? 0 : 1, @rows[index][:planned_term_uid], index ] }
      end

      def open_rows
        @open_rows ||= plan_rows.select { |index| @rows[index][:status] == "open" }
      end

      def fixed
        @rows.each_index.select { |index| DONE.include?(@rows[index][:status]) }
      end

      # The rows with a plan semester, in plan order.
      def plan_rows
        @plan_rows ||= @rows.each_index.select { |index| @rows[index][:planned_term_uid] }
                            .sort_by { |index| [ @rows[index][:planned_term_uid], index ] }
      end

      # A course row waits while its prerequisites need a row of the plan
      # that is not placed before the term. A course outside the plan that
      # the student did not take never makes it wait. So it waits when:
      # - the tree is not met with every course outside the plan counted, or
      # - the tree is not met with only the courses the student took, and
      #   it would be met with every row of the plan placed. This is an "or"
      #   with an old code outside the plan, such as COMP 2070 or COMP 285.
      # A slot or a choice names no single course, so it never waits.
      def blocked?(index, uid)
        row = @rows[index]
        return false unless row[:kind] == "course" && (pair = CatalogCourse.parse_code(row[:code]))

        tree = @prerequisites.prerequisites(pair)
        return false if tree.nil?

        not_met?(tree, uid, :passed, :placed) ||
          (not_met?(tree, uid, :not_met, :placed) && !not_met?(tree, uid, :not_met, :passed))
      end

      def not_met?(tree, uid, outside, plan)
        counted = Counted.new(waiting, @placed_at, uid, taken_keys, outside, plan)
        PrerequisiteCheck.new(counted, @aliases).call(tree)[:status] == PrerequisiteCheck::NOT_MET
      end

      # The courses the student did or takes, and the courses of the done
      # and in-progress rows.
      def taken_keys
        @taken_keys ||= @taken | fixed.flat_map { |index| keys(index) }
      end

      # The course keys that a prerequisite can wait for: the codes of the
      # open rows and of the rows the student takes after the current term,
      # with their aliases. A course the student did or takes now never
      # waits.
      def waiting
        @waiting ||= begin
          later = fixed.select { |index| (TermCode.parse(@rows[index][:term]) || 0) >= first_term }
          earlier = fixed - later
          (open_rows + later).flat_map { |index| keys(index) }.to_set - earlier.flat_map { |index| keys(index) }
        end
      end

      # The [subject, number] keys of a course row or of the options of a
      # choice, with their aliases.
      def keys(index)
        row = @rows[index]
        codes = row[:kind] == "choice" ? Array(row[:options]) : [ row[:code] ]
        codes.filter_map { |code| CatalogCourse.parse_code(code) if code }
             .flat_map { |pair| [ pair, *@aliases.fetch(pair, []) ] }.uniq
      end

      def co_op?(index) = CoOpRows.co_op?(@rows[index])

      # The plan's load for the term: the credits of the class rows of its
      # plan semester. A term with no class semester in the plan (a plan
      # co-op semester, or a term after the plan) takes the plan's average.
      def load(uid)
        plan_loads.fetch(uid) { average_load }
      end

      def plan_loads
        @plan_loads ||= plan_rows.reject { |index| co_op?(index) }
                                 .group_by { |index| @rows[index][:planned_term_uid] }
                                 .transform_values { |indexes| indexes.sum { |index| Rules.credits(@rows[index]) } }
      end

      def average_load
        @average_load ||= plan_loads.empty? ? Rules::MAX_TERM_CREDITS : (plan_loads.values.sum.to_f / plan_loads.size).round
      end

      # A fall or spring term takes classes. A summer term takes classes only
      # where the plan has a class row in that summer.
      def class_term?(uid) = !Rules.summer?(uid) || plan_loads.key?(uid)

      # A co-op can go in a fall or spring term, or in a summer term where
      # the plan has a semester.
      def co_op_usable?(uid) = !Rules.summer?(uid) || plan_summers.include?(uid)

      def plan_summers
        @plan_summers ||= plan_rows.map { |index| @rows[index][:planned_term_uid] }.select { |uid| Rules.summer?(uid) }.to_set
      end

      def first_term
        @first_term ||= Rules.next_term(@current)
      end

      def last_term
        @last_term ||= begin
          plan_end = plan_rows.map { |index| @rows[index][:planned_term_uid] }.max || @current
          Rules::EXTRA_TERMS.times.reduce([ plan_end, @current ].max) { |uid, _| Rules.next_term(uid) }
        end
      end
    end
  end
end
