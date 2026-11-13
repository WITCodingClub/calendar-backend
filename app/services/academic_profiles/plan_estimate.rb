# frozen_string_literal: true

module AcademicProfiles
  # The terms of an active program's plan, estimated from what the student
  # really took (#1011). It runs after PlanTerms, which gives the fixed plan
  # terms (#990). It is an estimate for planning, not a degree audit, and it
  # does not check that a term has sections of a course.
  #
  # It adds to the program entry:
  #
  # - expected_term, expected_term_uid, and moved on each requirement row.
  # - timeline: one entry for each term that has a row (by expected_term),
  #   each with basis: taken, plan, or estimate.
  # - expected_end: term is the estimate, plan_end is the plan end of #990.
  #
  # planned_term, planned_term_uid, and behind keep their meaning of #990.
  # Placement puts the rows in terms. Rules holds the rules that the co-op
  # office or the registrar can change.
  class PlanEstimate
    TAKEN = "taken"
    PLAN = "plan"
    ESTIMATE = "estimate"

    # start_term_uid and current_term_uid: Banner codes. prerequisites:
    # answers prerequisites([subject, number]) (CourseDetails). aliases:
    # each pair with its old and new pairs.
    def initialize(start_term_uid, current_term_uid:, prerequisites:, aliases: {})
      @start = start_term_uid
      @current = current_term_uid
      @prerequisites = prerequisites
      @aliases = aliases
    end

    # The program entry of PlanTerms with the estimate.
    def call(entry)
      rows = entry[:requirements]
      places = Placement.new(rows, current_term_uid: @current, prerequisites: @prerequisites, aliases: @aliases).call
      rows = rows.each_with_index.map do |row, index|
        uid, moved = places.fetch(index)
        row.merge(expected_term: TermCode.label(uid), expected_term_uid: uid, moved: moved)
      end
      timeline = timeline(rows)
      last = timeline.last

      entry.merge(
        requirements: rows,
        timeline:     timeline,
        expected_end: last && { term: last[:term], estimated: last[:estimated], plan_end: entry.dig(:expected_end, :term) }
      )
    end

    private

    def timeline(rows)
      rows.select { |row| row[:expected_term_uid] }.group_by { |row| row[:expected_term_uid] }.sort.map do |uid, term_rows|
        basis = basis_of(uid, term_rows, rows)
        year = year_of(uid)
        {
          term:      TermCode.label(uid),
          uid:       uid,
          year:      year,
          season:    Rules.season(uid),
          when:      PlanTerms.time_of(uid, @current),
          estimated: estimated?(basis, year),
          co_op:     term_rows.all? { |row| CoOpRows.co_op?(row) },
          basis:     basis
        }
      end
    end

    # taken: every row of the term is done or in progress. plan: the term
    # has the rows the plan puts in it, and no other. estimate: any other
    # term.
    def basis_of(uid, term_rows, rows)
      return TAKEN if term_rows.all? { |row| Placement::DONE.include?(row[:status]) }

      planned = rows.select { |row| row[:planned_term_uid] == uid }
      planned.size == term_rows.size && term_rows.all? { |row| row[:planned_term_uid] == uid } ? PLAN : ESTIMATE
    end

    # A taken term is not an estimate. A plan term is an estimate after
    # plan year 2, as in PlanTerms. Every other term is an estimate.
    def estimated?(basis, year)
      return false if basis == TAKEN
      return true if basis == ESTIMATE || year.nil?

      year > PlanTerms::EXACT_YEARS
    end

    # The plan year of a term, the inverse of ProgramTimeline.term_uid, so a
    # summer term after year 1 is in year 1. nil for a term before year 1,
    # such as a course taken before the program started.
    def year_of(uid)
      first_year = @start / 100
      first_year += 1 if Rules.summer?(@start)
      year = (uid / 100) - first_year + 1
      year.positive? ? year : nil
    end
  end
end
