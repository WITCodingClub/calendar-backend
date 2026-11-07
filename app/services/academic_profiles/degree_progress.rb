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
      "A D (passed_below_c) counts as done, but some requirements and prerequisites need a C or better.",
      "A course taken more than once counts once, with its best attempt.",
      "A course meets a requirement with the same code, or with an old or new code of the same course " \
      "(course code aliases). Substitutions, transfer credit, and AP credit are not known."
    ].freeze

    RANK = { "done" => 0, "in_progress" => 1, "not_passed" => 2 }.freeze
    PASSED = %w[c_or_better passed_below_c].freeze

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

    # include_planned also checks the student's planned programs (#867), so
    # the student sees the courses a planned minor adds. It does nothing with
    # a program argument.
    def initialize(user, program: nil, catalog_year: nil, plan: nil, include_planned: false, today: Time.zone.today)
      @user = user
      # A query string can be an array or a hash, so each value becomes text.
      @program = program.presence&.to_s
      @catalog_year = catalog_year.presence&.to_s
      @plan_name = plan.presence&.to_s
      @include_planned = include_planned
      @today = today
    end

    # Raises NoProgramError, or Catalog::FilterError for a bad catalog year.
    def call
      entries = requirement_sets
      raise NoProgramError, NO_PROGRAM_MESSAGE if entries.empty?

      {
        programs:    entries.map { |set, plan_name, row| program_json(set, plan_name, row) },
        courses:     taken.map(&:as_json),
        assumptions: ASSUMPTIONS
      }
    end

    private

    # The requirement sets to check, each with its plan name and the
    # student's row (nil for the program argument): the program argument, or
    # each active (and with include_planned, planned) program of the student
    # with a catalog link. The plan name is the plan argument, or the plan
    # the student picked (#867), or nil for the standard plan.
    def requirement_sets
      if @program
        set = find_argument_set(Catalog::ProgramQuery.new)
        return [ [ set, argument_plan_name(set), nil ] ]
      end

      statuses = @include_planned ? %w[active planned] : %w[active]
      rows = @user.student_programs.where(status: statuses).where.not(degree_program_id: nil)
                  .includes(:catalog_year).order(:id).select { |row| row.catalog_year&.imported? }
      sets = linked_sets(rows)

      rows.filter_map do |row|
        set = sets[[ row.degree_program_id, row.catalog_year_id ]]
        [ set, @plan_name || row.plan_name.presence, row ] if set
        # A planned row can have the same program as a later active row, for
        # example a minor the student then declared. Each keeps its entry.
      end.uniq { |set, _, row| [ set.id, row.status ] }
    end

    # The requirement set of each row, with what Catalog::ProgramQuery#find
    # loads, in one query for every row.
    def linked_sets(rows)
      return {} if rows.empty?

      RequirementSet.where(degree_program_id: rows.map(&:degree_program_id).uniq,
                           catalog_year_id: rows.map(&:catalog_year_id).uniq)
                    .includes(:catalog_year, degree_program: :parent_program,
                              program_plans: { items: :elective_group }, elective_groups: %i[courses program_plan])
                    .index_by { |set| [ set.degree_program_id, set.catalog_year_id ] }
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
      own = own_program&.catalog_year
      own&.imported? ? own : query.catalog_year(nil)
    end

    # The student's active row of the program argument, or nil.
    def own_program
      return @own_program if defined?(@own_program)

      @own_program = @user.student_programs.active.joins(:degree_program).includes(:catalog_year)
                          .find_by(degree_programs: { slug: @program.to_s.strip.downcase })
    end

    # The plan for the program argument: the plan argument, or the plan the
    # student picked for their own row of that program in the same catalog
    # year (#867).
    def argument_plan_name(set)
      return @plan_name if @plan_name

      own = own_program
      own.plan_name.presence if own && own.catalog_year_id == set.catalog_year_id
    end

    def program_json(set, plan_name, row)
      plan = pick_plan(set, plan_name)
      pool = attempts
      requirements = plan ? plan_requirements(set, plan, pool) : list_requirements(set, pool)
      open = requirements.reject { |requirement| requirement[:status] == "done" }

      {
        program:      set.degree_program.slug,
        # active or planned: the status of the student's row. nil for a
        # program argument.
        status:       row&.status,
        name:         set.name,
        catalog_year: set.catalog_year.name,
        # true for a plan read from a PDF that no person has checked yet.
        needs_review: set.needs_review,
        plan:         plan&.name,
        plans:        set.program_plans.map(&:name),
        counts:       %w[done in_progress open].index_with { |status| requirements.count { |r| r[:status] == status } },
        requirements: requirements,
        open:         open.map { |requirement| requirement.slice(:code, :label, :options, :elective_list, :status) }
      }
    end

    # The plan the student follows: the plan argument, or the plan the
    # student picked for the program (#867). Without one, the standard plan,
    # the same rule as RequirementSet#standard_plan, read from the loaded
    # plans. A picked plan that a later import renamed falls back to the
    # standard plan. An unknown plan argument raises FilterError.
    def pick_plan(set, plan_name)
      plans = set.program_plans.to_a
      picked = plan_name && plans.find { |plan| plan.name.casecmp?(plan_name) }
      return picked if picked

      if @plan_name
        raise Catalog::FilterError, "No plan #{@plan_name}. #{set.name} has: #{plans.map(&:name).join(', ')}"
      end

      plans.find { |plan| !plan.accelerated } || plans.first
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
      # A slot with a list of courses goes first, then a slot with a list of
      # subjects (an HSS elective), then a free elective. A broad slot then
      # does not use a course that a narrow one needs.
      slots = items.select(&:placeholder?).filter_map { |item| [ item, groups[item.elective_group_id] ] if item.elective_group_id }
      slots.sort_by.with_index { |(_, group), index| [ breadth(group), index ] }.each do |item, group|
        results[item.id] = take_for(pool, used, group)
      end

      items.map { |item| item_json(item, results[item.id]) }
    end

    def breadth(group)
      return 2 if group.any_course
      return 1 if group.subject_codes.any?

      0
    end

    # The best unused course that meets an elective list: a course on the
    # list, a course in one of its subjects, or any course.
    def take_for(pool, used, group)
      codes = group.courses.map { |course| [ course.subject_code, course.course_number ] }
      return take(pool, used, codes) unless group.any_course || group.subject_codes.any?

      keys = codes.flat_map { |code| equivalents(code) }
      take_where(pool, used) do |candidate|
        group.any_course || keys.include?(candidate.key) || group.subject_codes.include?(candidate.subject_code)
      end
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
        # A slot with no elective list, such as a "CONM Elective" whose page
        # prints no list, cannot be checked, so it stays open.
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
        next unchecked_list_json(group) unless countable?(group)

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

    # A list with no minimum that the import could read. A "Required ..."
    # list needs every course. Any other such list cannot be checked.
    def countable?(group)
      group.min_courses || group.min_credits || group.name.to_s.match?(/\Arequired\b/i)
    end

    def unchecked_list_json(group)
      { kind: "elective_list", elective_list: group.name, min_courses: nil, min_credits: nil, checkable: false,
        status: "open", courses: [] }
    end

    # The courses that can meet a requirement: the best attempt of each
    # course (a retake, or an old and a new code of one course, counts
    # once), without the ones not passed.
    def attempts
      @attempts ||= taken.group_by { |course| equivalents(course.key).min }
                         .values
                         .map { |tries| tries.min_by { |course| [ RANK.fetch(course.status), -course.term.uid ] } }
                         .reject { |course| course.status == "not_passed" }
    end

    # The best unused course that meets one of the codes: a done course
    # before one in progress. Marks it used.
    def take(pool, used, codes)
      keys = codes.flat_map { |code| equivalents(code) }.uniq
      take_where(pool, used) { |candidate| keys.include?(candidate.key) }
    end

    def take_where(pool, used)
      course = pool.reject { |candidate| used.include?(candidate) }
                   .select { |candidate| yield candidate }
                   .min_by { |candidate| RANK.fetch(candidate.status) }
      used << course if course
      course
    end

    # A code and its old or new codes (CourseCodeAlias), both ways. Only the
    # aliases a person checked count: the matches can pair two courses that
    # only share a title (#865).
    def equivalents(code)
      [ code, *aliases.fetch(code, []) ]
    end

    def aliases
      @aliases ||= CourseCodeAlias.reviewed.pluck(:from_subject_code, :from_course_number, :to_subject_code, :to_course_number)
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

        # A lecture and its lab share the code, so the sections of one course
        # in one term are one course: the most credits of a section (as
        # Catalog::ScheduleCheck counts them), and not passed when any
        # section was not passed.
        sections = enrollments.map(&:course).uniq.group_by { |course| [ course.term_id, course.subject, course.course_number ] }
        sections.values.map do |group|
          section_outcomes = group.to_h { |course| [ course, outcomes[[ course.term.uid, course.crn ]] ] }.compact
          failed = section_outcomes.find { |_, outcome| PASSED.exclude?(outcome) }
          course, outcome = failed || section_outcomes.first || [ group.first, nil ]
          Taken.new(course.subject, course.course_number, course.title, course.term, course.crn,
                    group.filter_map(&:credit_hours).max, taken_status(course.term, outcome), outcome)
        end.sort_by { |course| [ -course.term.uid, course.code ] }
      end
    end

    def taken_status(term, outcome)
      return PASSED.include?(outcome) ? "done" : "not_passed" if outcome
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
