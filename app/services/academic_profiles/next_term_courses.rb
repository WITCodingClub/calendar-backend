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
  # GET /api/user/next_term_courses and the My programs dashboard page send it.
  class NextTermCourses
    # A prerequisite tree node is met, not met, or unknown (a test score).
    MET = "met"
    NOT_MET = "not_met"
    UNKNOWN = "unknown"
    COUNTED = %w[done in_progress].freeze

    # term_uid: the Banner code of the term. Without one, the next fall or
    # spring term after the current term. Students register for fall in
    # the spring term, so a summer term is never the default.
    # programs and progress: the hashes of StudentProgramsSerializer and
    # DegreeProgress (active programs) when the caller already has them.
    # current_term_uid: the Banner code of the current term, Term.current
    # when not given.
    def initialize(user, term_uid: nil, current_term_uid: nil, programs: nil, progress: nil, today: Time.zone.today)
      @user = user
      @term_uid = term_uid
      @current_term_uid = current_term_uid
      @programs = programs
      @progress = progress
      @today = today
    end

    # Raises DegreeProgress::NoProgramError when no active program links to
    # the degree catalog.
    def call
      progress # raises NoProgramError before the rest
      {
        term:        { uid: term_uid, name: TermCode.label(term_uid) },
        sections:    sections_known?,
        programs:    program_entries,
        assumptions: [
          "A course in progress this term counts toward prerequisites, as if you pass it with a C or better.",
          "A prerequisite that needs a test score shows as unknown. A course with no prerequisite data from " \
          "Banner shows no prerequisite check.",
          "Behind rows are open rows of earlier plan semesters. Ask your advisor which ones to take first."
        ]
      }
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
      @progress ||= DegreeProgress.new(@user, today: @today).call
    end

    def program_entries
      # Two LeopardWeb rows can link to one catalog program, and
      # DegreeProgress checks it once.
      programs[:programs].uniq { |program| [ program[:program], program[:catalog_year], program[:status] ] }
                         .filter_map do |program|
        entry = progress[:programs].find do |candidate|
          candidate[:program] == program[:program] && candidate[:catalog_year] == program[:catalog_year] &&
            candidate[:status] == program[:status]
        end
        next if entry.nil? || entry[:plan].nil?

        program_json(program, entry)
      end
    end

    def program_json(program, entry)
      start = TermCode.parse(program[:start_term])
      rows = entry[:requirements].select { |row| row[:year] && row[:season] }
      planned, behind = [], []

      if start && term_uid
        rows.each do |row|
          uid = ProgramTimeline.term_uid(start, row[:year], row[:season])
          if uid == term_uid && COUNTED.exclude?(row[:status])
            planned << row_json(row)
          elsif uid < term_uid && uid <= behind_limit && row[:status] == "open"
            behind << row_json(row)
          end
        end
      end

      {
        program:    program[:program],
        name:       program[:name],
        plan:       entry[:plan],
        start_term: program[:start_term],
        # The plan semester of the term, such as year 2, spring. nil without a
        # start term, or when the term is after the end of the plan.
        semester:   start && term_uid && semester_of(rows, start),
        planned:    planned,
        behind:     behind
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

    def row_json(row)
      {
        year:          row[:year],
        season:        row[:season],
        kind:          row[:kind],
        code:          row[:code],
        label:         row[:label],
        elective_list: row[:elective_list],
        # The elective list of a slot, from DegreeProgress (#989), or nil.
        list:          row[:list],
        courses:       row_codes(row).map { |code| course_json(code) }
      }
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
      tree = catalog&.prerequisites.presence
      result = tree ? check(tree) : nil

      {
        code:          code,
        title:         catalog&.title,
        offered:       sections_known? ? keys.any? { |key| offered_codes.include?(key) } : nil,
        prerequisites: result && result[:status],
        missing:       result ? result[:missing] : []
      }.merge(CourseDetails.json(catalog).except(:title))
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

    # The courses from DegreeProgress that count, by [subject, number]: done
    # or in progress, in a term before the term. Banner does not let a
    # course in the same term meet a prerequisite.
    def counted_courses
      @counted_courses ||= progress[:courses].select { |course| COUNTED.include?(course[:status]) }
                                             .select { |course| term_uid.nil? || course[:term_uid] < term_uid }
                                             .group_by { |course| CatalogCourse.parse_code(course[:code]) }
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

    def offered_codes
      @offered_codes ||= Course.active.where(term: term).distinct.pluck(:subject, :course_number)
                               .to_set { |subject, number| "#{subject} #{number}" }
    end
  end
end
