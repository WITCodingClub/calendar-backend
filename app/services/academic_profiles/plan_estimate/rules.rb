# frozen_string_literal: true

module AcademicProfiles
  class PlanEstimate
    # The rules of the estimate that a later answer from the co-op office or
    # the registrar can change. Each rule is one constant or one method.
    module Rules
      # "20 credits is max per semester without an overload code" (Jasper,
      # 2026-11-12). A term takes about the plan's load for its semester, and
      # never more than this.
      MAX_TERM_CREDITS = 20

      # The credits of a row with no credit hours: an open elective slot or
      # choice, or a course that CatalogCourse does not know. Most WIT
      # courses have 4 credits.
      DEFAULT_CREDITS = 4

      # The estimate stops this many terms (three years) after the later of
      # the plan's last semester and the current term. A row that it cannot
      # place by then, such as a row in a prerequisite cycle, gets no
      # expected term.
      EXTRA_TERMS = 9

      FALL_AND_SPRING = %w[fall spring].freeze

      module_function

      # "you cant usually take classes during coop semester without
      # approval" (Jasper, 2026-11-12). A co-op term gets no classes.
      def classes_in_co_op_term? = false

      # The co-op office has no fixed spacing rule: "spacing is major
      # dependent, the catalog site does outline the typical cadence, but as
      # long as you meet the coop requirements you can do it whenever you
      # like it" (Jasper, 2026-11-12). So the estimate keeps the cadence of
      # the student's plan: a co-op comes this many co-op terms after the
      # previous co-op, the same gap as in the plan. It is never less than 1.
      def co_op_gap(previous_planned_uid, planned_uid, usable)
        [ steps(previous_planned_uid, planned_uid, usable), 1 ].max
      end

      # The credits of a row: the credit hours of its course, or of the
      # course that fills a slot or a choice, or DEFAULT_CREDITS.
      def credits(row)
        hours = row[:kind] == "course" ? row[:credit_hours] : row.dig(:filled_course, :credit_hours)
        hours || DEFAULT_CREDITS
      end

      # A course with typically_offered of only fall or only spring goes in
      # a term it is offered. A null or empty list, or a list with both fall
      # and spring, places it anywhere. Only a course row has the list.
      def offered_in?(row, uid)
        seasons = Array(row[:typically_offered])
        return true if (seasons & FALL_AND_SPRING).size != 1

        seasons.include?(season(uid))
      end

      def season(uid) = TermCode::SEASON_SUFFIXES.key(uid % 100)

      def summer?(uid) = season(uid) == "summer"

      # The Banner code of the next term: fall, spring, summer, fall.
      def next_term(uid)
        uid % 100 == TermCode::SEASON_SUFFIXES.fetch("summer") ? ((uid / 100) + 1) * 100 + 10 : uid + 10
      end

      # The number of terms after from, up to and including to, for which
      # usable is true.
      def steps(from, to, usable)
        count = 0
        uid = next_term(from)
        while uid <= to
          count += 1 if usable.call(uid)
          uid = next_term(uid)
        end
        count
      end

      # The term count usable terms after from.
      def advance(from, count, usable)
        uid = from
        count.times do
          uid = next_term(uid)
          uid = next_term(uid) until usable.call(uid)
        end
        uid
      end
    end
  end
end
