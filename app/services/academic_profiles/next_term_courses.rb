# frozen_string_literal: true

module AcademicProfiles
  # The courses the plan of study puts in the term a student registers for
  # next (#449), for each active program. It reads the plan rows of
  # DegreeProgress and the start term of each program (ProgramTimeline), so a
  # student does not have to read the program page of the catalog.
  #
  # For each program it gives:
  # - planned: the rows of the plan semester that falls in the term, without
  #   the rows already done or in progress.
  # - behind: open rows of earlier plan semesters. The student did not take
  #   them yet, so they can also go into the term.
  # - registered: the courses of the term that the student already
  #   registered for and that fill a row of the program (#1019), with their
  #   CRNs, so a client can start the plan of the term from them.
  #
  # Each course in a row tells if the term has a section of it (nil when
  # WIT Calendar has no sections of the term yet) and if the student meets
  # its prerequisites with the courses done or in progress. It is a help for
  # planning, not a degree audit or a registration check.
  #
  # With assume or assume_plans (#996), it also counts the assumed courses
  # (AssumedCourses) as passed before the term, and the hash lists them in
  # assumed. Each course also has missing_in_plan: the courses of missing
  # that a planned or behind row of the term names.
  #
  # With include_candidates (#993), each elective slot and choice row also
  # has candidates: the courses of the term that can fill it
  # (ElectiveCandidates).
  #
  # GET /api/user/next_term_courses and the My programs dashboard page send it.
  class NextTermCourses
    # The outcomes of the courses that count for PrerequisiteCheck: the
    # taken courses (by key), and each assumed course as passed with a C or
    # better (no outcome).
    Counted = Struct.new(:taken, :assumed) do
      def counted(key)
        outcomes = taken.fetch(key, []).pluck(:outcome)
        assumed.include?(key) ? [ *outcomes, nil ] : outcomes
      end
    end
    CANDIDATE_KINDS = %w[placeholder choice].freeze

    # term_uid: the Banner code of the term. Without one, the next fall or
    # spring term after the current term. Students register for fall in
    # the spring term, so a summer term is never the default.
    # programs and progress: the hashes of StudentProgramsSerializer and
    # DegreeProgress (active programs) when the caller already has them.
    # current_term_uid: the Banner code of the current term, Term.current
    # when not given.
    # assume: [subject, number] pairs (AssumedCourses.parse) to count as
    # passed. assume_plans: also count the courses of the saved registration
    # plans of the terms between the current term and the term.
    # include_candidates: add candidates to each elective slot and choice.
    def initialize(user, term_uid: nil, current_term_uid: nil, programs: nil, progress: nil, assume: [],
                   assume_plans: false, include_candidates: false, today: Time.zone.today)
      @user = user
      @term_uid = term_uid
      @current_term_uid = current_term_uid
      @programs = programs
      @progress = progress
      @assume = assume
      @assume_plans = assume_plans
      @include_candidates = include_candidates
      @today = today
    end

    # Raises DegreeProgress::NoProgramError when no active program links to
    # the degree catalog.
    def call
      progress # raises NoProgramError before the rest
      {
        term:        { uid: term_uid, name: TermCode.label(term_uid) },
        # Only with assume or assume_plans, so the hash stays the same
        # without them.
        **(assumed_courses.requested? ? { assumed: assumed_courses.to_h } : {}),
        sections:    sections_known?,
        programs:    program_entries,
        assumptions: [
          "A course in progress this term counts toward prerequisites, as if you pass it with a C or better.",
          "A course you registered for in a later term counts toward prerequisites in the terms after it, " \
          "as if you pass it with a C or better.",
          ("A course in assumed counts toward prerequisites, as if you pass it with a C or better." if assumed_courses.pairs.any?),
          "A prerequisite that needs a test score shows as unknown. A course with no prerequisite data from " \
          "Banner shows no prerequisite check.",
          "Behind rows are open rows of earlier plan semesters. Ask your advisor which ones to take first.",
          ("Candidates are recommendations, not a registration check. Banner checks restrictions when you " \
           "register." if @include_candidates)
        ].compact
      }
    end

    def term_uid
      @term_uid ||= current_term_uid && TermCode.next_regular_term(current_term_uid)
    end

    private

    def current_term_uid
      @current_term_uid ||= Term.current_uid
    end

    def programs
      @programs ||= StudentProgramsSerializer.new(@user).as_json
    end

    def progress
      # The rows carry no course details: course_json loads them with the
      # prerequisites, in one query (#989).
      @progress ||= DegreeProgress.new(@user, course_details: false, today: @today).call
    end

    def program_entries
      term_rows.map { |program, entry, planned, behind| program_json(program, entry, planned, behind) }
    end

    # [program, DegreeProgress entry, planned rows, behind rows] for each
    # active program with a plan of study.
    def term_rows
      # Two LeopardWeb rows can link to one catalog program, and
      # DegreeProgress checks it once.
      @term_rows ||= programs[:programs].uniq { |program| [ program[:program], program[:catalog_year], program[:status] ] }
                                        .filter_map do |program|
        entry = DegreeProgress.entry_for(progress, program)
        next if entry.nil? || entry[:plan].nil?

        [ program, entry, *split_rows(entry) ]
      end
    end

    # The rows by planned term (PlanTerms). A row has none without a start
    # term.
    def split_rows(entry)
      planned, behind = [], []
      return [ planned, behind ] unless term_uid

      plan_rows(entry).each do |row|
        uid = row[:planned_term_uid]
        next if uid.nil?

        if uid == term_uid && !CourseHistory.counted?(row[:status])
          planned << row
        elsif uid < term_uid && uid <= behind_limit && row[:status] == "open"
          behind << row
        end
      end
      [ planned, behind ]
    end

    def plan_rows(entry)
      entry[:requirements].select { |row| row[:year] && row[:season] }
    end

    def program_json(program, entry, planned, behind)
      {
        program:    program[:program],
        name:       program[:name],
        plan:       entry[:plan],
        start_term: program[:start_term],
        # The plan semester of the term, such as year 2, spring. nil without a
        # start term, or when the term is after the end of the plan.
        semester:   term_uid && semester_of(plan_rows(entry)),
        planned:    planned.map { |row| row_json(entry, row) },
        behind:     behind.map { |row| row_json(entry, row) },
        registered: registered_json(entry)
      }
    end

    # The registered courses of the term (#1019) whose code, or an alias of
    # it, is the course of a row of the program. Their rows are in neither
    # planned nor behind. A retake counts too: the row keeps the best
    # attempt, such as a D in an earlier term, and the retake is in the
    # term. Each course once, in plan order.
    def registered_json(entry)
      codes = entry[:requirements].filter_map { |row| row[:course] if CourseHistory.counted?(row[:status]) }
      codes.flat_map { |code| term_registered.select { |course| course_keys.equivalent_codes(code).include?(course[:code]) } }
           .uniq { |course| course[:code] }
           .map { |course| { code: course[:code], title: course[:title], crns: term_crns.fetch(course[:code], []) } }
    end

    def term_registered
      @term_registered ||= progress[:courses].select { |course| course[:term_uid] == term_uid && course[:status] == "registered" }
    end

    # The CRNs of the student's sections in the term, by course code. A
    # lecture and its lab share the code, so a course can have more than
    # one CRN.
    def term_crns
      @term_crns ||= if term.nil?
        {}
      else
        @user.courses.where(term: term).order(:crn)
             .pluck(Arel.sql(Course::SUBJECT_CODE_SQL), :course_number, :crn)
             .group_by { |subject, number, _| CourseCode.format(subject, number) }
             .transform_values { |rows| rows.map(&:last).uniq }
      end
    end

    # A row is behind only when its term started: the current term or
    # earlier. A row between the current term and a later term argument is
    # still ahead.
    def behind_limit
      @behind_limit ||= [ current_term_uid, term_uid ].compact.min
    end

    def semester_of(rows)
      row = rows.find { |candidate| candidate[:planned_term_uid] == term_uid }
      row && { year: row[:year], season: row[:season] }
    end

    def row_json(entry, row)
      json = {
        year:          row[:year],
        season:        row[:season],
        kind:          row[:kind],
        code:          row[:code],
        label:         row[:label],
        elective_list: row[:elective_list],
        # The elective list of a slot, from DegreeProgress (#989), or nil.
        list:          row[:list],
        # The HSS category that the slot still needs, from DegreeProgress
        # (#991), or nil.
        hss_category:  row[:hss_category],
        courses:       row_codes(row).map { |code| course_json(code) }
      }
      return json unless @include_candidates && CANDIDATE_KINDS.include?(row[:kind])

      json.merge(candidates: elective_candidates.for(entry, row))
    end

    def elective_candidates
      @elective_candidates ||= ElectiveCandidates.new(
        term: term, taken: progress[:courses], prerequisites: ->(catalog) { prerequisite_json(catalog) },
        entries: term_rows.map { |_program, entry, planned, behind| [ entry, planned + behind ] },
        # An assumed course counts as passed, and a course row of the term
        # takes its course, so neither can fill a slot.
        skip: assumed_courses.pairs + term_course_rows
      )
    end

    def term_course_rows
      term_rows.flat_map { |_program, _entry, planned, behind| planned + behind }
               .select { |row| row[:kind] == "course" }
               .filter_map { |row| CourseCode.parse(row[:code]) }
    end

    # The courses a row names: its code, or the options of a choice. An
    # elective slot names a list, not a course.
    def row_codes(row)
      case row[:kind]
      when "course" then [ row[:code] ].compact
      when "choice" then row[:options]
      else []
      end
    end

    def course_json(code)
      key = CourseCode.parse(code)
      catalog = key && catalog_courses.catalog(key)

      {
        code:    code,
        title:   catalog&.title,
        offered: sections_known? ? course_keys.equivalent_codes(code).any? { |found| offered_codes.include?(found) } : nil,
        **prerequisite_json(catalog)
      }.merge(CourseDetails.json(catalog).except(:title))
    end

    # The prerequisite check of a CatalogCourse (or nil): the status, the
    # missing courses, and the ones a row of the term names.
    def prerequisite_json(catalog)
      tree = catalog&.prerequisites.presence
      result = tree && prerequisite_check.call(tree)
      { prerequisites: result && result[:status], missing: result ? result[:missing] : [],
        missing_in_plan: result ? missing_in_plan(result[:missing_keys]) : [] }
    end

    def prerequisite_check
      @prerequisite_check ||= PrerequisiteCheck.new(Counted.new(taken_courses, assumed_courses.pairs.to_set), course_keys)
    end

    # The missing courses that a planned or behind row of the term names, in
    # any program, also through an alias.
    def missing_in_plan(keys)
      keys.select { |key| course_keys.equivalents(key).any? { |found| term_row_keys.include?(found) } }
          .map { |key| CourseCode.format(*key) }
    end

    def term_row_keys
      @term_row_keys ||= course_keys.expand(term_rows.flat_map { |_program, _entry, planned, behind| planned + behind }
                                                     .flat_map { |row| row_codes(row) }
                                                     .filter_map { |code| CourseCode.parse(code) }).to_set
    end

    # The courses from DegreeProgress that count, by [subject, number]: done
    # or in progress, in a term before the term. Banner does not let a
    # course in the same term meet a prerequisite. A transfer credit (#1020)
    # has no term and always counts.
    def taken_courses
      @taken_courses ||= progress[:courses].select { |course| CourseHistory.counted?(course[:status]) }
                                           .select { |course| term_uid.nil? || course[:term_uid].nil? || course[:term_uid] < term_uid }
                                           .group_by { |course| CourseCode.parse(course[:code]) }
    end

    # The assumed courses, without the ones the student did or takes (also
    # through an alias). A course passed below C stays, because a retake can
    # meet a minimum grade of C.
    def assumed_courses
      @assumed_courses ||= AssumedCourses.new(
        @user, term_uid: term_uid, current_term_uid: current_term_uid, codes: @assume, plans: @assume_plans,
               skip: ->(pair) { taken_with_c?(pair) }
      )
    end

    def taken_with_c?(pair)
      course_keys.equivalents(pair).any? do |key|
        taken_courses.fetch(key, []).any? { |course| course[:outcome] != CourseOutcome::PASSED_BELOW_C }
      end
    end

    def course_keys = CourseKeys.current

    # The catalog rows of every course a row of a program names.
    def catalog_courses
      @catalog_courses ||= CourseDetails.new(progress[:programs].flat_map { |entry| entry[:requirements] }
                                                                .flat_map { |row| row_codes(row) }
                                                                .filter_map { |code| CourseCode.parse(code) }, course_keys)
    end

    def term
      return @term if defined?(@term)

      @term = term_uid && Term.find_by(uid: term_uid)
    end

    # True when WIT Calendar has sections of the term, so a course with no
    # section is not offered.
    def sections_known?
      return @sections_known if defined?(@sections_known)

      @sections_known = term.present? && Course.where(term: term).exists?
    end

    # A section stores its subject as a label, such as "Computer Science
    # (COMP)", so the codes take the code in it (Course::SUBJECT_CODE_SQL).
    def offered_codes
      @offered_codes ||= Course.active.where(term: term).distinct
                               .pluck(Arel.sql(Course::SUBJECT_CODE_SQL), :course_number)
                               .to_set { |subject, number| CourseCode.format(subject, number) }
    end
  end
end
