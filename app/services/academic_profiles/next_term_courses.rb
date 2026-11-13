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
    # A prerequisite tree node is met, not met, or unknown (a test score).
    MET = "met"
    NOT_MET = "not_met"
    UNKNOWN = "unknown"
    COUNTED = %w[done in_progress].freeze
    # An assumed course counts as passed with a C or better.
    ASSUMED = { status: "assumed", outcome: nil }.freeze
    # A course code inside a missing entry, such as "WDGT 1100 or WDGT 1200".
    MISSING_CODE = /[A-Z]{2,5} \d{3,4}/
    # The rows that get candidates.
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
          ("A course in assumed counts toward prerequisites, as if you pass it with a C or better." if assumed_courses.pairs.any?),
          "A prerequisite that needs a test score shows as unknown. A course with no prerequisite data from " \
          "Banner shows no prerequisite check.",
          "Behind rows are open rows of earlier plan semesters. Ask your advisor which ones to take first.",
          ("Candidates are recommendations, not a registration check. Banner checks restrictions when you " \
           "register." if @include_candidates)
        ].compact
      }
    end

    # true when an include value names candidates. It takes "candidates",
    # a list separated by commas ("candidates,other"), or an array.
    def self.candidates_requested?(value)
      values = value.is_a?(Array) ? value : [ value ]
      values.flat_map { |item| item.is_a?(String) ? item.split(",") : [] }.map(&:strip).include?("candidates")
    end

    def term_uid
      @term_uid ||= self.class.default_term_uid(current_term_uid)
    end

    # The next fall or spring term after the current term, as a Banner code,
    # or nil with no current term.
    def self.default_term_uid(current_uid = Term.current_uid)
      return nil if current_uid.nil?

      year = current_uid / 100
      current_uid % 100 == TermCode::SEASON_SUFFIXES.fetch("fall") ? (year * 100) + 20 : ((year + 1) * 100) + 10
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
        entry = progress[:programs].find do |candidate|
          candidate[:program] == program[:program] && candidate[:catalog_year] == program[:catalog_year] &&
            candidate[:status] == program[:status]
        end
        next if entry.nil? || entry[:plan].nil?

        [ program, entry, *split_rows(program, entry) ]
      end
    end

    def split_rows(program, entry)
      start = TermCode.parse(program[:start_term])
      planned, behind = [], []
      return [ planned, behind ] unless start && term_uid

      plan_rows(entry).each do |row|
        uid = ProgramTimeline.term_uid(start, row[:year], row[:season])
        if uid == term_uid && COUNTED.exclude?(row[:status])
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
      start = TermCode.parse(program[:start_term])

      {
        program:    program[:program],
        name:       program[:name],
        plan:       entry[:plan],
        start_term: program[:start_term],
        # The plan semester of the term, such as year 2, spring. nil without a
        # start term, or when the term is after the end of the plan.
        semester:   start && term_uid && semester_of(plan_rows(entry), start),
        planned:    planned.map { |row| row_json(entry, row) },
        behind:     behind.map { |row| row_json(entry, row) }
      }
    end

    # A row is behind only when its term started: the current term or
    # earlier. A row between the current term and a later term argument is
    # still ahead.
    def behind_limit
      @behind_limit ||= [ current_term_uid, term_uid ].compact.min
    end

    def semester_of(rows, start)
      row = rows.find { |candidate| ProgramTimeline.term_uid(start, candidate[:year], candidate[:season]) == term_uid }
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
               .filter_map { |row| CatalogCourse.parse_code(row[:code]) }
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
      keys = equivalent_codes(code)
      catalog = keys.lazy.filter_map { |key| catalog_courses[key] }.first

      {
        code:    code,
        title:   catalog&.title,
        offered: sections_known? ? keys.any? { |key| offered_codes.include?(key) } : nil,
        **prerequisite_json(catalog)
      }.merge(CourseDetails.json(catalog).except(:title))
    end

    # The prerequisite check of a CatalogCourse (or nil): the status, the
    # missing courses, and the ones a row of the term names.
    def prerequisite_json(catalog)
      tree = catalog&.prerequisites.presence
      result = tree ? check(tree) : nil
      missing = result ? result[:missing] : []
      { prerequisites: result && result[:status], missing: missing, missing_in_plan: missing_in_plan(missing) }
    end

    # status of one prerequisite tree node, and the courses not met under it.
    def check(node)
      case node["type"]
      when "and", "or"
        results = node["operands"].map { |operand| check(operand) }
        statuses = results.pluck(:status)
        status = if node["type"] == "and"
          if statuses.all?(MET) then MET
          elsif statuses.include?(NOT_MET) then NOT_MET
          else UNKNOWN
          end
        elsif statuses.include?(MET) then MET
        elsif statuses.all?(NOT_MET) then NOT_MET
        else UNKNOWN
        end
        { status: status, missing: status == MET ? [] : missing_of(node["type"], results) }
      when "course"
        code = "#{node['subject_code']} #{node['course_number']}"
        status = course_status(node["subject_code"], node["course_number"].to_i, node["min_grade"])
        { status: status, missing: status == MET ? [] : [ code ] }
      else
        { status: UNKNOWN, missing: [] }
      end
    end

    # The missing courses of an and or an or node. The options of an or
    # are one entry, such as "WDGT 1100 or WDGT 1200", so a reader does not
    # think it needs both.
    def missing_of(type, results)
      lists = results.map { |result| result[:missing] }.reject(&:empty?)
      return lists.flatten.uniq if type == "and"

      lists.map { |list| list.size == 1 ? list.first : "(#{list.join(' and ')})" }.uniq.then do |options|
        options.size > 1 ? [ options.join(" or ") ] : options
      end
    end

    # met when the student did or takes the course or an alias of it before
    # the term, with a grade the minimum allows. Outcomes say only "C or
    # better" or "passed below C", so a minimum above C is unknown.
    def course_status(subject, number, min_grade)
      keys = [ [ subject, number ], *aliases.fetch([ subject, number ], []) ]
      courses = keys.flat_map { |key| counted_courses.fetch(key, []) }
      return NOT_MET if courses.empty?

      grade = min_grade.to_s.strip.upcase
      return MET if grade.empty? || grade.start_with?("D")
      return UNKNOWN unless grade.start_with?("C")

      courses.any? { |course| course[:outcome] != "passed_below_c" } ? MET : NOT_MET
    end

    # The course codes of missing that a planned or behind row of the term
    # names, in any program, also through an alias. A missing entry with
    # options, such as "WDGT 1100 or WDGT 1200", gives each of its codes
    # that a row names.
    def missing_in_plan(missing)
      missing.flat_map { |entry| entry.scan(MISSING_CODE) }.uniq.select do |code|
        equivalent_codes(code).any? { |key| term_row_codes.include?(key) }
      end
    end

    def term_row_codes
      @term_row_codes ||= term_rows.flat_map { |_program, _entry, planned, behind| planned + behind }
                                   .flat_map { |row| row_codes(row) }
                                   .flat_map { |code| equivalent_codes(code) }
                                   .to_set
    end

    # The courses that count, by [subject, number]: the taken courses and
    # the assumed courses.
    def counted_courses
      @counted_courses ||= assumed_courses.pairs.each_with_object(taken_courses.dup) do |pair, map|
        map[pair] = [ *map[pair], ASSUMED ]
      end
    end

    # The courses from DegreeProgress that count, by [subject, number]: done
    # or in progress, in a term before the term. Banner does not let a
    # course in the same term meet a prerequisite.
    def taken_courses
      @taken_courses ||= progress[:courses].select { |course| COUNTED.include?(course[:status]) }
                                           .select { |course| term_uid.nil? || course[:term_uid] < term_uid }
                                           .group_by { |course| CatalogCourse.parse_code(course[:code]) }
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
      [ pair, *aliases.fetch(pair, []) ].any? do |key|
        taken_courses.fetch(key, []).any? { |course| course[:outcome] != "passed_below_c" }
      end
    end

    # A code and its old or new codes, as "SUBJ 1234".
    def equivalent_codes(code)
      pair = CatalogCourse.parse_code(code)
      return [ code ] if pair.nil?

      [ pair, *aliases.fetch(pair, []) ].map { |subject, number| "#{subject} #{number}" }.uniq
    end

    def aliases
      @aliases ||= CourseCodeAlias.pluck(:from_subject_code, :from_course_number, :to_subject_code, :to_course_number)
                                  .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(fs, fn, ts, tn), map|
        map[[ fs, fn ]] << [ ts, tn ]
        map[[ ts, tn ]] << [ fs, fn ]
      end
    end

    def all_codes
      @all_codes ||= program_rows.flat_map { |row| row_codes(row) }.flat_map { |code| equivalent_codes(code) }.uniq
    end

    def program_rows
      progress[:programs].flat_map { |entry| entry[:requirements] }
    end

    def catalog_courses
      @catalog_courses ||= begin
        pairs = all_codes.filter_map { |code| CatalogCourse.parse_code(code) }
        if pairs.empty?
          {}
        else
          pairs.group_by(&:first)
               .map { |subject, list| CatalogCourse.where(subject_code: subject, course_number: list.map(&:last)) }
               .reduce(:or)
               .index_by(&:code)
        end
      end
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
    # (COMP)", so the codes take the code in it (Course.prefix_of).
    def offered_codes
      @offered_codes ||= Course.active.where(term: term).distinct
                               .pluck(Arel.sql(Course::SUBJECT_CODE_SQL), :course_number)
                               .to_set { |subject, number| "#{subject} #{number}" }
    end
  end
end
