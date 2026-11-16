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
    class NoProgramError < PlanningError
      def code = "no_program"
    end

    NO_PROGRAM_MESSAGE = "WIT Calendar has no major with a catalog year for this student that links to the " \
                         "degree catalog. The WIT Calendar browser extension reads the programs from the Student " \
                         "Profile page in LeopardWeb when the student processes a term. Ask the student to open " \
                         "the extension and process a term, or pass program and catalog_year."

    ASSUMPTIONS = [
      "A course in a past term with no outcome from LeopardWeb counts as passed.",
      "A course in the current term with no outcome counts as in progress.",
      "A course in a term after the current term counts as registered: the student registered for it. " \
      "For prerequisites, it counts as passed with a C or better in the terms after its term.",
      "A failed, withdrawn, or incomplete course does not count.",
      "A D (passed_below_c) counts as done, but some requirements and prerequisites need a C or better.",
      "A course taken more than once counts once, with its best attempt.",
      "A course meets a requirement with the same code, or with an old or new code of the same course " \
      "(course code aliases). Substitutions are not known.",
      "AP, test, and transfer credit comes from the LeopardWeb transcript or from the student. It counts as a " \
      "done course with no term, but it needs approval from the program director to count. A course taken at " \
      "WIT wins over a transfer credit for the same course."
    ].freeze

    # include_planned also checks the student's planned programs (#867), so
    # the student sees the courses a planned minor adds. It does nothing with
    # a program argument. course_details: false leaves out the catalog
    # details of the rows (#989) and their query, for a caller that does not
    # send them, such as NextTermCourses.
    def initialize(user, program: nil, catalog_year: nil, plan: nil, include_planned: false, course_details: true,
                   today: Time.zone.today)
      @user = user
      # A query string can be an array or a hash, so each value becomes text.
      @selection = ProgramSelection.new(user, program: program.presence&.to_s, catalog_year: catalog_year.presence&.to_s,
                                              plan: plan.presence&.to_s, include_planned: include_planned)
      @include_planned = include_planned
      @with_details = course_details
      @today = today
    end

    # The entry of a result for a program of StudentProgramsSerializer, or
    # nil. Two LeopardWeb rows can link to one catalog program, and the
    # result has one entry for it.
    def self.entry_for(result, program)
      return nil if program[:program].nil?

      result[:programs].find do |entry|
        entry.values_at(:program, :catalog_year, :status) == program.values_at(:program, :catalog_year, :status)
      end
    end

    # Raises PlanningError, or Catalog::ProgramQuery::FilterError for a
    # program or catalog year that the catalog does not have.
    def call
      entries = @selection.entries
      raise NoProgramError, NO_PROGRAM_MESSAGE if entries.empty?

      @course_details = CourseDetails.new(@with_details ? detail_codes(entries) : [], course_keys)
      @credits = CourseCredits.new(@course_details)
      programs = entries.map { |set, plan_name, row| with_terms(program_json(set, plan_name, row), row) }
      # The lists and the overlap (#992) read the planned terms of the active
      # programs, so they come after with_terms of every program.
      # The open slots (#998) need the elective lists of the active sets.
      active = entries.zip(programs).select { |_, entry| entry[:status] == "active" }
      slots = {}.compare_by_identity
      active.each { |(set, plan_name, _), entry| slots[entry] = fit_slots(set, plan_name, entry) } if @include_planned
      overlap = ProgramOverlap.new(active.map(&:last), course_keys: course_keys, attempts: attempts,
                                                       course_details: @course_details, credits: @credits, slots: slots,
                                                       hss_matcher: hss_matcher)
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
    # student row, so it has no start term. An active program then gets the
    # estimate from the student's history (PlanEstimate, #1011).
    def with_terms(entry, row)
      start = row && ProgramTimeline.new(row, requirement_set: nil, admit_term_uid: admit_term_uid).start_term_uid
      entry = PlanTerms.new(start, current_term_uid: current_term&.uid).call(entry)
      entry = estimate(entry, start) if estimate?(entry, row, start)
      HssDetails.with_open_slots(entry)
    end

    # The estimate needs a start term, a current term, a plan of study, and
    # the course details (credits, terms offered, prerequisites). A planned
    # program and a program argument keep the fields of #990 only.
    def estimate?(entry, row, start)
      @with_details && row&.status == "active" && start && entry[:plan] && current_term
    end

    def estimate(entry, start)
      PlanEstimate.new(start, current_term_uid: current_term.uid, prerequisites: @course_details, course_keys: course_keys,
                              taken: attempts.map(&:key)).call(entry)
    end

    def admit_term_uid
      return @admit_term_uid if defined?(@admit_term_uid)

      @admit_term_uid = @user.academic_profile&.admit_term_uid
    end

    def program_json(set, plan_name, row)
      plan = @selection.plan(set, plan_name)
      # counted: the courses that fill a row of this program (#1012).
      requirements, hss, counted = plan ? plan_requirements(set, plan) : list_requirements(set)
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
        counts:       [ *CourseHistory::STATUSES, "open" ].index_with { |status| requirements.count { |r| r[:status] == status } },
        summary:      summary_json(set, requirements, counted),
        requirements: requirements,
        open:         open.map { |requirement| requirement.slice(:code, :label, :options, :elective_list, :status) },
        # The humanities and social science requirement of the major, or nil
        # when the plan has no HSS slot.
        hss:          hss
      }
    end

    # Rows of a plan of study. Returns the rows, the HSS entry, and the
    # courses that fill the rows.
    def plan_requirements(set, plan)
      fill = requirement_fill.plan(set, plan)
      rows = plan.items.map { |item| item_json(item, fill.courses[item.id], fill.needs[item.id]) }
      [ rows, hss_json(fill), fill.counted ]
    end

    # The HSS requirement of the major (HssDetails).
    def hss_json(fill)
      return nil if fill.hss.nil?

      HssDetails.new(fill.hss, english: fill.english, slot_courses: fill.hss_slots, matcher: hss_matcher, credits: @credits).call
    end

    # A program with no plan of study, such as a minor: each elective list
    # with its minimum. Returns the rows, no HSS entry, and the courses the
    # lists count.
    def list_requirements(set)
      lists, counted = requirement_fill.lists(set)
      rows = lists.map do |list|
        list.courses ? list_json(list.group, list.courses, list.needed) : unchecked_list_json(list.group)
      end
      [ rows, nil, counted ]
    end

    def requirement_fill
      @requirement_fill ||= RequirementFill.new(attempts, course_keys: course_keys, credits: @credits, hss_matcher: hss_matcher)
    end

    def hss_matcher
      @hss_matcher ||= HssMatcher.new(course_keys)
    end

    # The open elective slots of an active program that a course of a planned
    # minor can fill (#998): the open plan rows with an elective list, without
    # the co-op slots. An HSS slot that stands for a category (hss_category)
    # takes only a course of that category. The rows are in the order of the
    # plan items, so each row has its item. ProgramSelection#plan gives the
    # same plan as program_json, also when two plans have the same name.
    def fit_slots(set, plan_name, entry)
      plan = @selection.plan(set, plan_name)
      return [] if plan.nil? || plan.items.size != entry[:requirements].size

      groups = set.elective_groups.index_by(&:id)
      plan.items.zip(entry[:requirements]).filter_map do |item, row|
        group = groups[item.elective_group_id]
        next unless item.placeholder? && group && row[:status] == "open"
        next if group.shared_kind == :co_op

        category = row[:hss_category] && HssMatcher.categories(set).find { |found| found["name"] == row[:hss_category] }
        MinorFit::Slot.new(label: row[:label], term: row[:planned_term], term_uid: row[:planned_term_uid],
                           rule: requirement_fill.list_rule(group), category: category)
      end
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
        options:       item.options.map { |option| CourseCode.format(option["subject_code"], option["course_number"]) },
        elective_list: item.elective_group&.name,
        hss_category:  hss_category,
        # A slot with no elective list, such as a "CONM Elective" whose page
        # prints no list, cannot be checked, so it stays open.
        checkable:     !item.placeholder? || item.elective_group.present?,
        status:        course ? course.status : "open",
        course:        course&.code,
        term:          course&.term&.name,
        # true when an AP, test, or transfer credit fills the row (#1020).
        transfer:      course&.transfer || false
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
        details = @course_details.for(item.key)
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
      (rows + lists).map(&:key) + taken.map(&:key)
    end

    # The program totals (#989, #1012). credits sums the credits of the
    # courses that fill a row of this program (counted), each course once:
    # done courses are earned, courses in progress are in_progress, and
    # courses in a later term are registered (#1019).
    # not_counted has the other best attempts the student passed or takes,
    # such as ENGL 700 or a course past a list's minimum. A third English
    # course that counts as Humanities fills no row, so it is not counted
    # here, but hss.credits counts it. Each course counts by CourseCredits.
    # co_ops counts the co-op semester
    # rows of the plan and the done ones.
    def summary_json(set, requirements, counted)
      co_ops = requirements.select { |row| CoOpRows.co_op?(row) }
      other = attempts - counted
      {
        total_credits: set.total_credits,
        school:        set.school_name,
        department:    set.department_name,
        credits:       {
          earned:      credits_with(counted, "done"),
          in_progress: credits_with(counted, "in_progress"),
          registered:  credits_with(counted, "registered"),
          not_counted: { earned: credits_with(other, "done"), in_progress: credits_with(other, "in_progress"),
                         registered: credits_with(other, "registered"), courses: other.sort_by(&:key).map(&:code) }
        },
        co_ops:        { required: co_ops.size, done: co_ops.count { |row| row[:status] == "done" } }
      }
    end

    def credits_with(courses, status)
      @credits.sum(courses.select { |course| course.status == status })
    end

    def list_json(group, courses, needed)
      met = needed ? courses.size >= needed : @credits.sum(courses) >= group.min_credits
      # A met list has the status of its latest course: registered when one
      # course is in a later term.
      status = if !met then "open"
      elsif courses.all? { |course| course.status == "done" } then "done"
      elsif courses.any? { |course| course.status == "registered" } then "registered"
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

    def unchecked_list_json(group)
      { kind: "elective_list", elective_list: group.name, min_courses: nil, min_credits: nil, checkable: false,
        status: "open", courses: [] }
    end

    def course_keys
      @course_keys ||= CourseKeys.current
    end

    def history
      @history ||= CourseHistory.new(@user, course_keys: course_keys, today: @today)
    end

    def taken = history.taken

    def attempts = history.attempts

    def current_term = history.current_term
  end
end
