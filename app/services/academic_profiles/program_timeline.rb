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
  #   start puts "Year 1, fall" in Fall 2025.
  #
  # GET /api/user/programs, the my_programs MCP tool, and the My programs
  # dashboard page read it through StudentProgramSerializer.
  class ProgramTimeline
    PLAN_SOURCES = %w[student assumed].freeze

    attr_reader :program, :requirement_set

    # A timeline for each program, keyed by program, with two queries for the
    # requirement sets and their plans.
    def self.for_programs(programs, admit_term_uid:)
      linked = programs.select { |program| program.degree_program_id && program.catalog_year_id }
      sets = if linked.empty?
        {}
      else
        RequirementSet.where(degree_program_id: linked.map(&:degree_program_id).uniq,
                             catalog_year_id: linked.map(&:catalog_year_id).uniq)
                      .includes(:program_plans)
                      .index_by { |set| [ set.degree_program_id, set.catalog_year_id ] }
      end

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

    # The plan with this name, case ignored, or nil.
    def plan_named(name) = plans.find { |plan| plan.name.casecmp?(name.to_s.strip) }

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

    # The Banner code of the term of one plan semester, or nil without a
    # start term. A Banner code names the academic year that ends in its
    # year (Fall 2025 is 202610), so the year of the code moves by one for
    # each plan year.
    def term_uid(year_index, season) = self.class.term_uid(start_term_uid, year_index, season)

    def self.term_uid(start_term_uid, year_index, season)
      suffix = TermCode::SEASON_SUFFIXES[season.to_s]
      return nil if start_term_uid.nil? || suffix.nil? || year_index.nil?

      (((start_term_uid / 100) + year_index - 1) * 100) + suffix
    end

    private

    def picked_plan
      return nil if program.plan_name.blank?

      plan_named(program.plan_name)
    end

    # The first plan that is not accelerated, as RequirementSet#standard_plan,
    # read from the loaded plans.
    def standard_plan
      plans.find { |candidate| !candidate.accelerated } || plans.first
    end
  end
end
