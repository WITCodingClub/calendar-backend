# frozen_string_literal: true

module AcademicProfiles
  # The requirement rows of the student's active programs, as the courses they
  # name (#992). A row names a course row's code, the options of a choice, and
  # the course that fills it, each with its old and new codes (CourseKeys).
  # ProgramOverlap compares a planned program with them, and the My programs
  # page marks the courses a planned program adds (added_rows).
  class ActiveRows
    # One row of an active program: the course keys it names and its planned
    # term.
    Row = Struct.new(:keys, :term, :term_uid)

    # active_entries: the DegreeProgress entries of the active programs, with
    # the fields of PlanTerms.
    def initialize(active_entries, course_keys)
      @active = active_entries
      @course_keys = course_keys
      @others = {}
      @rows_of = {}.compare_by_identity
    end

    # The rows of the active programs without the program itself: a planned
    # minor that the student also declared does not overlap with itself.
    def other_than(program)
      @others[program] ||= @active.reject { |entry| entry[:program] == program }.flat_map { |entry| of(entry) }
    end

    def of(entry)
      @rows_of[entry] ||= entry[:requirements].filter_map do |row|
        keys = @course_keys.expand([ *self.class.keys(row), CourseCode.parse(row[:course]) ].compact)
        Row.new(keys.to_set, row[:planned_term], row[:planned_term_uid]) if keys.any?
      end
    end

    # The rows of a planned program that are not done, each with shared:
    # true when an active program also has the course. For a choice, one
    # shared option is enough.
    def added_rows(entry)
      rows = other_than(entry[:program])
      entry[:requirements].reject { |row| row[:status] == "done" }.map do |row|
        { row: row, shared: self.class.keys(row).any? { |key| rows.any? { |active| active.keys.include?(key) } } }
      end
    end

    # The keys a requirement row names: its code and the options of a choice.
    def self.keys(row)
      [ row[:code], *row[:options] ].compact.filter_map { |code| CourseCode.parse(code) }
    end
  end
end
