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
    # The codes of a co-op semester, as "COOP 3500".
    CO_OP_CODES = DegreeRequirements::SharedElectives::CO_OP_TERMS.map { |code| code.join(" ") }.freeze

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
    # a program argument. course_details: false leaves out the catalog
    # details of the rows (#989) and their query, for a caller that does not
    # send them, such as NextTermCourses.
    def initialize(user, program: nil, catalog_year: nil, plan: nil, include_planned: false, course_details: true,
                   today: Time.zone.today)
      @user = user
      # A query string can be an array or a hash, so each value becomes text.
      @program = program.presence&.to_s
      @catalog_year = catalog_year.presence&.to_s
      @plan_name = plan.presence&.to_s
      @include_planned = include_planned
      @with_details = course_details
      @today = today
    end

    # Raises NoProgramError, or Catalog::FilterError for a bad catalog year.
    def call
      entries = requirement_sets
      raise NoProgramError, NO_PROGRAM_MESSAGE if entries.empty?

      @course_details = CourseDetails.new(@with_details ? detail_codes(entries) : [], aliases)
      programs = entries.map { |set, plan_name, row| with_terms(program_json(set, plan_name, row), row) }
      # The lists and the overlap (#992) read the planned terms of the active
      # programs, so they come after with_terms of every program.
      overlap = ProgramOverlap.new(programs.select { |entry| entry[:status] == "active" },
                                   aliases: aliases, attempts: attempts, course_details: @course_details)
      {
        programs:    entries.zip(programs).map { |(set, _, _), entry| overlap.call(set, entry) },
        courses:     taken.map(&:as_json),
        assumptions: ASSUMPTIONS
      }
    end

    private

    # The real terms of the plan (#990): start_term, timeline, expected_end,
    # and the planned term of each row. The start term is the one of
    # GET /api/user/programs (ProgramTimeline). A program argument has no
    # student row, so it has no start term.
    def with_terms(entry, row)
      start = row && ProgramTimeline.new(row, requirement_set: nil, admit_term_uid: admit_term_uid).start_term_uid
      HssDetails.with_open_slots(PlanTerms.new(start, current_term_uid: current_term&.uid).call(entry))
    end

    # The admit term of the academic profile, read once for every program.
    def admit_term_uid
      return @admit_term_uid if defined?(@admit_term_uid)

      @admit_term_uid = @user.academic_profile&.admit_term_uid
    end

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
                          .find_by(degree_programs: { slug: DegreeProgram.current_slug(@program.to_s.strip.downcase) })
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
      requirements, hss = plan ? plan_requirements(set, plan, pool) : [ list_requirements(set, pool), nil ]
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
        summary:      summary_json(set, requirements),
        requirements: requirements,
        open:         open.map { |requirement| requirement.slice(:code, :label, :options, :elective_list, :status) },
        # The humanities and social science requirement of the major, or nil
        # when the plan has no HSS slot.
        hss:          hss
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
      hss_slots, slots = slots.partition { |_, group| group.name == DegreeRequirements::SharedElectives::HSS.name }
      needs = {}
      narrow, broad = slots.partition { |_, group| !group.any_course }
      narrow.sort_by.with_index { |(_, group), index| [ breadth(group), width(group), index ] }.each do |item, group|
        results[item.id] = take_for(pool, used, group)
      end
      hss = hss_progress(set, items, groups, results, pool, used)
      assign_hss(hss, hss_slots, results, needs, pool, used)
      broad.each { |item, group| results[item.id] = take_for(pool, used, group) }

      rows = items.map { |item| item_json(item, results[item.id], needs[item.id]) }
      [ rows, hss_json(hss, items, groups, results) ]
    end

    # What counts toward the HSS requirement before the "HSS Elective" slots
    # take a course: the courses in the other HSS slots (Humanities Elective,
    # a directed course), the required course rows in an HSS category
    # (ECON4102 in Construction Management, PHIL4525 in Applied AI), and a
    # third English course, which the notes let count as Humanities. nil for
    # a program with no HSS requirement and no HSS slot.
    def hss_progress(set, items, groups, results, pool, used)
      slots = items.any? { |item| hss_group?(groups[item.elective_group_id]) }
      return nil if set.hss_requirement.blank? && !slots

      categories = HssMatcher.categories(set)
      rows = items.reject(&:placeholder?).filter_map { |item| results[item.id] }
                  .select { |course| categories.any? { |category| hss_matcher.in_category?(category, course) } }
      english = take_where(pool, used) { |candidate| english_sequence?(candidate) } if english_slots_full?(items, groups, results)
      { categories: categories, min_credits: set.hss_requirement&.dig("min_credits"), english_humanities: english,
        met: hss_courses(items, groups, results) + rows + [ english ].compact, rows: rows }
    end

    def english_sequence?(course)
      DegreeRequirements::SharedElectives::ENGLISH_SEQUENCE.any? { |code| equivalents(code).include?(course.key) }
    end

    def english_slots_full?(items, groups, results)
      slots = items.select { |item| groups[item.elective_group_id]&.name == DegreeRequirements::SharedElectives::ENGLISH.name }
      slots.any? && slots.all? { |item| results[item.id] }
    end

    # The HSS slots of a plan, such as "HSS Elective", take courses so that
    # the major's categories are met: one humanities course, one social
    # science course, an Ethics course, ... (RequirementSet#hss_requirement).
    # A course in another HSS slot (Humanities Elective, a directed course)
    # already counts. Each slot takes a course for the first category that
    # no course meets yet, or stays open for it, and names it in needs.
    # With every category met, a slot takes any HSS course.
    def assign_hss(hss, slots, results, needs, pool, used)
      return if slots.empty? || hss.nil?

      met = hss[:met].dup
      categories = hss[:categories].select { |category| HssMatcher.checkable?(category) }
      slots.each do |item, group|
        category = categories.find do |candidate|
          met.none? { |course| hss_matcher.in_category?(candidate, course, english_humanities: hss[:english_humanities]) } &&
            needs.values.exclude?(candidate["name"])
        end
        if category
          needs[item.id] = category["name"]
          course = take_where(pool, used) { |candidate| hss_matcher.in_category?(category, candidate) }
        else
          course = take_for(pool, used, group)
        end
        results[item.id] = course
        met << course if course
      end
    end

    # The courses in the HSS slots of a plan.
    def hss_courses(items, groups, results)
      items.select { |item| item.placeholder? && hss_group?(groups[item.elective_group_id]) }.filter_map { |item| results[item.id] }
    end

    def hss_group?(group) = HssMatcher.slot_list?(group&.name)

    # The HSS categories and matching rules (HssMatcher), with the course
    # code aliases of this student.
    def hss_matcher
      @hss_matcher ||= HssMatcher.new(aliases)
    end

    # The HSS requirement of the major (HssDetails).
    def hss_json(hss, items, groups, results)
      return nil if hss.nil?

      english = items.select { |item| groups[item.elective_group_id]&.name == DegreeRequirements::SharedElectives::ENGLISH.name }
                     .filter_map { |item| results[item.id] }
      HssDetails.new(hss, english: english, slot_courses: hss_courses(items, groups, results), matcher: hss_matcher).call
    end

    def breadth(group)
      return 2 if group.any_course
      return 1 if group.subject_codes.any?

      0
    end

    # Among lists of one kind, the shorter list first: "Humanities" before
    # "HSS".
    def width(group) = group.subject_codes.any? ? group.subject_codes.size : group.courses.size

    # The best unused course that meets an elective list: a course on the
    # list, a course in one of its subjects, or any course. Any course means
    # a course for degree credit: not a co-op and not a course below 1000,
    # such as ENGL0700.
    def take_for(pool, used, group)
      codes = group.courses.map { |course| [ course.subject_code, course.course_number ] }
      return take(pool, used, codes) unless group.any_course || group.subject_codes.any?

      keys = codes.flat_map { |code| equivalents(code) }
      take_where(pool, used) do |candidate|
        (group.any_course && degree_credit?(candidate)) || keys.include?(candidate.key) ||
          group.subject_codes.include?(candidate.subject_code)
      end
    end

    def degree_credit?(course)
      course.subject_code != "COOP" && course.course_number.to_i >= 1000
    end

    # hss_category: the category of the major's HSS requirement that a
    # generic HSS slot stands for, such as "Ethics", or nil.
    def item_json(item, course, hss_category = nil)
      {
        year:          item.year_index,
        season:        item.season,
        kind:          item.kind,
        code:          item.code,
        label:         item.label,
        options:       item.options.map { |option| "#{option['subject_code']} #{option['course_number']}" },
        elective_list: item.elective_group&.name,
        hss_category:  hss_category,
        # A slot with no elective list, such as a "CONM Elective" whose page
        # prints no list, cannot be checked, so it stays open.
        checkable:     !item.placeholder? || item.elective_group.present?,
        status:        course ? course.status : "open",
        course:        course&.code,
        term:          course&.term&.name
      }.merge(details_json(item, course))
    end

    # The catalog details of a plan row (#989). A course row gets the details
    # of its course. Every row gets the elective list it draws from, or nil.
    # An elective slot or a choice gets the course that fills it, or nil.
    def details_json(item, course)
      json = { list: elective_list_json(item.elective_group) }
      if item.course?
        # A course with no CatalogCourse row keeps the title of the section
        # that meets the row.
        details = @course_details.for([ item.subject_code, item.course_number ])
        return json.merge(details, title: details[:title] || course&.title)
      end

      json.merge(filled_course: course && filled_course_json(course))
    end

    def elective_list_json(group)
      return nil if group.nil?

      { heading: group.heading, notes: group.notes, min_courses: group.min_courses, min_credits: group.min_credits,
        subject_codes: group.subject_codes }
    end

    # A course with no CatalogCourse row keeps the title of its section.
    def filled_course_json(course)
      details = @course_details.for(course.key)
      { code: course.code, **details, title: details[:title] || course.title }
    end

    # The codes to load details for: the course rows of each plan, the
    # courses the student took, which fill the slots and choices, and the
    # courses on the lists of a program with no plan (#992).
    def detail_codes(entries)
      rows = entries.flat_map { |set, _, _| set.program_plans.flat_map(&:items) }.select(&:course?)
      lists = entries.flat_map { |set, _, _| set.program_plans.empty? ? set.elective_groups.flat_map(&:courses) : [] }
      (rows + lists).map { |course| [ course.subject_code, course.course_number ] } + taken.map(&:key)
    end

    # The program totals (#989). credits sums the credits of the courses the
    # student took, each course once with its best attempt, as the rows count
    # them: done courses are earned, courses in progress are in_progress. A
    # course whose sections have no credit hours takes those of CatalogCourse.
    # co_ops counts the co-op semester rows of the plan and the done ones.
    def summary_json(set, requirements)
      co_ops = requirements.select { |row| co_op_row?(row) }
      {
        total_credits: set.total_credits,
        school:        set.school_name,
        department:    set.department_name,
        credits:       { earned: credits_with("done"), in_progress: credits_with("in_progress") },
        co_ops:        { required: co_ops.size, done: co_ops.count { |row| row[:status] == "done" } }
      }
    end

    def credits_with(status)
      attempts.select { |course| course.status == status }
              .sum { |course| (course.credits || @course_details.for(course.key)[:credit_hours]).to_i }
    end

    # A slot in the Co-op list, or a course row that names a co-op semester
    # (COOP3500, COOP4500, COOP5000). COOP2500 is a normal course.
    def co_op_row?(row)
      return row[:elective_list] == DegreeRequirements::SharedElectives::CO_OP.name if row[:kind] == "placeholder"

      row[:kind] == "course" && CO_OP_CODES.include?(row[:code])
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
      @aliases ||= CourseCodeAlias.reviewed_pairs
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
