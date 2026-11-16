# frozen_string_literal: true

module AcademicProfiles
  # The plan of study and the start term of one StudentProgram (#867), and
  # the real term of each semester of the plan: with a Fall 2025 start,
  # "Year 3, fall" is Fall 2027.
  #
  # - The plan is the one the student picked (plan_name, source "student"),
  #   or the standard plan of the program's catalog year (source "assumed").
  #   A program with no plan of study, such as a minor, has no plan.
  # - The start term is the program's catalog term from LeopardWeb, which is
  #   the term the student started the program. Without one, it is the admit
  #   term of the profile. A planned program has no start term.
  # - Year 1 of a plan is the academic year of the start term. A Spring 2026
  #   start puts "Year 1, fall" in Fall 2025. A summer start counts as the
  #   start of the next academic year.
  #
  # GET /api/user/programs, the my_programs MCP tool, and the My programs
  # dashboard page read it through StudentProgramSerializer.
  class ProgramTimeline
    PLAN_SOURCES = %w[student assumed].freeze

    attr_reader :program, :requirement_set

    # A timeline for each program, keyed by program, with two queries for the
    # requirement sets and their plans.
    def self.for_programs(programs, admit_term_uid:)
      sets = RequirementSet.includes(:program_plans).index_for(programs)

      programs.to_h do |program|
        set = sets[[ program.degree_program_id, program.catalog_year_id ]]
        [ program, new(program, requirement_set: set, admit_term_uid: admit_term_uid) ]
      end
    end

    # One program. Loads its requirement set and the admit term when not
    # given.
    def self.for_program(program)
      for_programs([ program ], admit_term_uid: program.user.academic_profile&.admit_term_uid).fetch(program)
    end

    def initialize(program, requirement_set:, admit_term_uid:)
      @program = program
      @requirement_set = requirement_set
      @admit_term_uid = admit_term_uid
    end

    def plans = requirement_set ? requirement_set.program_plans.to_a : []

    def plan_names = plans.map(&:name)

    def plan_named(name) = requirement_set&.plan_named(name)

    # The plan the student picked, or the standard plan.
    def plan = picked_plan || standard_plan

    # "student" when the student picked the plan, "assumed" for the
    # standard plan, nil with no plan.
    def plan_source
      return nil if plan.nil?

      picked_plan ? "student" : "assumed"
    end

    def start_term_uid
      return program.catalog_term_uid if program.catalog_term_uid
      return nil if program.planned?

      @admit_term_uid
    end

    # "catalog_term" or "admit_term": where the start term came from.
    def start_term_source
      return "catalog_term" if program.catalog_term_uid
      return nil if start_term_uid.nil?

      "admit_term"
    end

    def term_uid(year_index, season) = TermCode.plan_term(start_term_uid, year_index, season)

    # One plan semester of the rows of DegreeProgress: its plan year and
    # season, its term (nil without a start term), and its rows.
    Semester = Data.define(:year, :season, :uid, :rows)

    # The plan semesters of the rows with a year and a season, in plan order
    # (fall, spring, summer in each year). DegreeProgress (#990) and the My
    # programs dashboard page read it.
    def self.semesters(start_term_uid, rows)
      rows.select { |row| row[:year] && row[:season] }
          .group_by { |row| [ row[:year], row[:season] ] }
          .sort_by { |(year, season), _| [ year, TermCode::SEASON_SUFFIXES.fetch(season, 99) ] }
          .map do |(year, season), semester_rows|
            Semester.new(year: year, season: season, uid: TermCode.plan_term(start_term_uid, year, season), rows: semester_rows)
          end
    end

    private

    def picked_plan
      return nil if program.plan_name.blank?

      plan_named(program.plan_name)
    end

    def standard_plan = requirement_set&.standard_plan
  end
end
