# frozen_string_literal: true

module AcademicProfiles
  # A student's degree requirements next to the courses they took or take
  # (#799). GET /api/user/degree_progress and the MCP tool my_degree_progress
  # send it. It is a help for planning, not a degree audit: the official
  # audit is Stellic.
  #
  # The programs are the student's active programs that link to the degree
  # catalog (AcademicProfiles::ProgramMatcher), each with its own catalog
  # year. A program argument checks one catalog program in place of them.
  #
  # Each course the student took counts toward one requirement only. Required
  # courses take a course first, then choices, then elective slots, so an
  # elective slot does not use a course a required row needs.
  class DegreeProgress
    # Raised when there is no program to check. The message says how to add
    # one. The tool and the endpoint pass it to the student.
    class NoProgramError < StandardError; end

    NO_PROGRAM_MESSAGE = "WIT Calendar has no major with a catalog year for this student that links to the " \
                         "degree catalog. The WIT Calendar browser extension reads the programs from the Student " \
                         "Profile page in LeopardWeb when the student processes a term. Ask the student to open " \
                         "the extension and process a term, or pass program and catalog_year."

    ASSUMPTIONS = [
      "A course in a past term with no outcome from LeopardWeb counts as passed.",
      "A course in the current or a future term counts as in progress.",
      "A failed, withdrawn, or incomplete course does not count.",
      "A course meets a requirement with the same code, or with an old or new code of the same course " \
      "(course code aliases). Substitutions, transfer credit, and AP credit are not known."
    ].freeze

    RANK = { "done" => 0, "in_progress" => 1 }.freeze

    # A course the student took or takes. status is done, in_progress, or
    # not_passed.
    Taken = Struct.new(:subject_code, :course_number, :title, :term, :crn, :credits, :status, :outcome) do
      def code = "#{subject_code} #{course_number}"
      def key = [ subject_code, course_number ]

      def as_json(*)
        { code: code, title: title, term: term.name, term_uid: term.uid, crn: crn, credits: credits,
          status: status, outcome: outcome }
      end
    end

    def initialize(user, program: nil, catalog_year: nil, plan: nil, today: Time.zone.today)
      @user = user
      # A query string can be an array or a hash, so each value becomes text.
      @program = program.presence&.to_s
      @catalog_year = catalog_year.presence&.to_s
      @plan_name = plan.presence&.to_s
      @today = today
    end

    # Raises NoProgramError, or Catalog::FilterError for a bad catalog year.
    def call
      sets = requirement_sets
      raise NoProgramError, NO_PROGRAM_MESSAGE if sets.empty?

      {
        programs:    sets.map { |set| program_json(set) },
        courses:     taken.map(&:as_json),
        assumptions: ASSUMPTIONS
      }
    end

    private

    # The requirement sets to check: the program argument, or each active
    # program of the student with a catalog link.
    def requirement_sets
      query = Catalog::ProgramQuery.new
      return [ find_argument_set(query) ] if @program

      @user.student_programs.active.includes(:catalog_year, :degree_program).order(:id).filter_map do |program|
        next if program.degree_program_id.nil? || !program.catalog_year&.imported?

        query.find(program.degree_program.slug, catalog_year: program.catalog_year)
      end.uniq
    end

    def find_argument_set(query)
      year = @catalog_year ? query.catalog_year(@catalog_year) : own_catalog_year(query)
      raise Catalog::FilterError, "No #{@catalog_year || 'imported'} catalog in WIT Calendar" if year.nil?

      query.find(@program, catalog_year: year) ||
        raise(Catalog::FilterError, "No program #{@program} in the #{year.name} catalog. Call list_programs to find the slug.")
    end

    # The catalog year of the student's own program with this slug, or the
    # newest catalog year.
    def own_catalog_year(query)
      own = @user.student_programs.active.joins(:degree_program).includes(:catalog_year)
                 .find_by(degree_programs: { slug: @program.to_s.strip.downcase })&.catalog_year
      own&.imported? ? own : query.catalog_year(nil)
    end

    def program_json(set)
      plan = pick_plan(set)
      pool = taken.reject { |course| course.status == "not_passed" }
      requirements = plan ? plan_requirements(set, plan, pool) : list_requirements(set, pool)
      open = requirements.reject { |requirement| requirement[:status] == "done" }

      {
        program:      set.degree_program.slug,
        name:         set.name,
        catalog_year: set.catalog_year.name,
        plan:         plan&.name,
        plans:        set.program_plans.map(&:name),
        counts:       %w[done in_progress open].index_with { |status| requirements.count { |r| r[:status] == status } },
        requirements: requirements,
        open:         open.map { |requirement| requirement.slice(:code, :label, :options, :elective_list, :status) }
      }
    end

    # The plan the student follows. Without a plan argument, the standard
    # plan, the same rule as RequirementSet#standard_plan, read from the
    # loaded plans.
    def pick_plan(set)
      plans = set.program_plans.to_a
      return plans.find { |plan| !plan.accelerated } || plans.first if @plan_name.nil?

      set.program_plans.find { |plan| plan.name.casecmp?(@plan_name) } ||
        raise(Catalog::FilterError, "No plan #{@plan_name}. #{set.name} has: #{set.program_plans.map(&:name).join(', ')}")
    end

    # Rows of a plan of study. Course rows take a course first, then choice
    # rows, then elective slots.
    def plan_requirements(set, plan, pool)
      groups = set.elective_groups.index_by(&:id)
      items = plan.items.to_a
      results = {}
      used = []

      items.select(&:course?).each do |item|
        results[item.id] = take(pool, used, [ [ item.subject_code, item.course_number ] ])
      end
      items.select(&:choice?).each do |item|
        results[item.id] = take(pool, used, item.options.map { |option| [ option["subject_code"], option["course_number"].to_i ] })
      end
      items.select(&:placeholder?).each do |item|
        group = groups[item.elective_group_id]
        results[item.id] = group ? take(pool, used, group.courses.map { |course| [ course.subject_code, course.course_number ] }) : nil
      end

      items.map { |item| item_json(item, results[item.id]) }
    end

    def item_json(item, course)
      {
        year:          item.year_index,
        season:        item.season,
        kind:          item.kind,
        code:          item.code,
        label:         item.label,
        options:       item.options.map { |option| "#{option['subject_code']} #{option['course_number']}" },
        elective_list: item.elective_group&.name,
        # A slot with no elective list, such as a free elective, cannot be
        # checked, so it stays open.
        checkable:     !item.placeholder? || item.elective_group.present?,
        status:        course ? course.status : "open",
        course:        course&.code,
        term:          course&.term&.name
      }
    end

    # A program with no plan of study, such as a minor: each elective list
    # with its minimum.
    def list_requirements(set, pool)
      used = []
      set.elective_groups.map do |group|
        codes = group.courses.map { |course| [ course.subject_code, course.course_number ] }
        needed = group.min_courses || (group.min_credits ? nil : codes.size)
        courses = []
        while (course = take(pool, used, codes))
          courses << course
          break if needed && courses.size >= needed
          break if needed.nil? && courses.sum { |c| c.credits.to_i } >= group.min_credits
        end
        list_json(group, courses, needed)
      end
    end

    def list_json(group, courses, needed)
      met = needed ? courses.size >= needed : courses.sum { |c| c.credits.to_i } >= group.min_credits
      status = if !met then "open"
      elsif courses.all? { |course| course.status == "done" } then "done"
      else "in_progress"
      end

      {
        kind:          "elective_list",
        elective_list: group.name,
        min_courses:   group.min_courses,
        min_credits:   group.min_credits,
        checkable:     true,
        status:        status,
        courses:       courses.map(&:code)
      }
    end

    # The best unused course that meets one of the codes: a done course
    # before one in progress. Marks it used.
    def take(pool, used, codes)
      keys = codes.flat_map { |code| equivalents(code) }.uniq
      course = pool.reject { |candidate| used.include?(candidate) }
                   .select { |candidate| keys.include?(candidate.key) }
                   .min_by { |candidate| RANK.fetch(candidate.status) }
      used << course if course
      course
    end

    # A code and its old or new codes (CourseCodeAlias), both ways.
    def equivalents(code)
      [ code, *aliases.fetch(code, []) ]
    end

    def aliases
      @aliases ||= CourseCodeAlias.pluck(:from_subject_code, :from_course_number, :to_subject_code, :to_course_number)
                                  .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(fs, fn, ts, tn), map|
        map[[ fs, fn ]] << [ ts, tn ]
        map[[ ts, tn ]] << [ fs, fn ]
      end
    end

    # Each enrolled course, newest term first.
    def taken
      @taken ||= begin
        enrollments = @user.enrollments.includes(course: :term).to_a
        outcomes = CourseOutcome.where(user: @user).to_h { |outcome| [ [ outcome.term_uid, outcome.crn ], outcome.outcome ] }

        enrollments.map(&:course).uniq.map do |course|
          outcome = outcomes[[ course.term.uid, course.crn ]]
          Taken.new(course.subject, course.course_number, course.title, course.term, course.crn, course.credit_hours,
                    taken_status(course.term, outcome), outcome)
        end.sort_by { |course| [ -course.term.uid, course.code ] }
      end
    end

    def taken_status(term, outcome)
      return %w[c_or_better passed_below_c].include?(outcome) ? "done" : "not_passed" if outcome
      return "done" if past?(term)

      "in_progress"
    end

    # A term with no end date (an old term) is past when it is before the
    # current term.
    def past?(term)
      return term.end_date < @today if term.end_date

      current = current_term
      current.present? && term.uid < current.uid
    end

    def current_term
      return @current_term if defined?(@current_term)

      @current_term = Term.current
    end
  end
end
