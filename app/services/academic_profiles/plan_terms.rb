# frozen_string_literal: true

module AcademicProfiles
  # The real terms of the plan of one program of DegreeProgress (#990). It
  # adds to the program entry:
  #
  # - start_term: the start term of ProgramTimeline, the same value as
  #   GET /api/user/programs. nil for a planned program and a program
  #   argument.
  # - timeline: one entry for each plan semester, in plan order, with its
  #   term. Empty without a start term or without a plan of study.
  # - expected_end: the last semester of the timeline, or nil.
  # - planned_term, planned_term_uid, and behind on each requirement row.
  #
  # The term of a plan semester comes from ProgramTimeline.term_uid. It keeps
  # the order of the plan: a co-op or a summer class can move the real terms.
  class PlanTerms
    PAST = "past"
    CURRENT = "current"
    REGISTERING = "registering"
    FUTURE = "future"
    # A semester after plan year 2 is an estimate.
    EXACT_YEARS = 2

    # start_term_uid: the Banner code of the program's start term, or nil.
    # current_term_uid: the Banner code of Term.current, or nil.
    def initialize(start_term_uid, current_term_uid:)
      @start = start_term_uid
      @current = current_term_uid
    end

    # The program entry of DegreeProgress with the term fields.
    def call(entry)
      semesters = @start ? ProgramTimeline.semesters(@start, entry[:requirements]) : []
      timeline = semesters.map { |semester| semester_json(semester) }
      last = timeline.last

      entry.merge(
        start_term:   TermCode.label(@start),
        expected_end: last && { term: last[:term], estimated: last[:estimated] },
        timeline:     timeline,
        requirements: entry[:requirements].map { |row| row.merge(row_terms(row)) }
      )
    end

    # past, current, registering, or future. A summer term between the
    # current term and the registering term is future: the registering term
    # is the next fall or spring term, as in NextTermCourses. nil without a
    # current term. PlanEstimate also uses it.
    def self.time_of(uid, current)
      return nil if current.nil?
      return PAST if uid < current
      return CURRENT if uid == current
      return REGISTERING if uid == NextTermCourses.default_term_uid(current)

      FUTURE
    end

    private

    def semester_json(semester)
      {
        term:      TermCode.label(semester.uid),
        uid:       semester.uid,
        year:      semester.year,
        season:    semester.season,
        when:      time_of(semester.uid),
        estimated: semester.year > EXACT_YEARS,
        co_op:     semester.rows.all? { |row| CoOpRows.co_op?(row) }
      }
    end

    # A row with no plan semester (an elective list of a minor) or no start
    # term has no planned term and is never behind.
    def row_terms(row)
      uid = ProgramTimeline.term_uid(@start, row[:year], row[:season])
      { planned_term: TermCode.label(uid), planned_term_uid: uid, behind: behind?(row, uid) }
    end

    # The same rule as the behind rows of NextTermCourses: an open row whose
    # term started (the current term or earlier).
    def behind?(row, uid)
      !uid.nil? && !@current.nil? && row[:status] == "open" && uid <= @current
    end

    def time_of(uid) = self.class.time_of(uid, @current)
  end
end
