# frozen_string_literal: true

module AcademicProfiles
  # The course lists of a program with no plan of study, such as a minor, and
  # the overlap of a planned program with the student's active programs
  # (#992). DegreeProgress calls it for each program after PlanTerms, so the
  # planned terms of the active programs are at hand. The My programs page
  # uses added_rows for "Courses it adds".
  #
  # A course of an active program is a course row, an option of a choice
  # row, or the course that fills a row. A code matches through a checked
  # CourseCodeAlias, as in the rest of DegreeProgress. See
  # docs/degree-requirements.md for the rules and a worked example.
  class ProgramOverlap
    # The credits of a course with no credit hours, and of each course still
    # to take on a list with a credit minimum.
    ASSUMED_CREDITS = 3

    # One row of an active program: the course keys it names (with their
    # aliases) and its planned term.
    ActiveRow = Struct.new(:keys, :term, :term_uid)

    # "MATH 1750" as [ "MATH", 1750 ], or nil.
    def self.key(code)
      subject, number = code.to_s.split(" ", 2)
      [ subject, number.to_i ] if subject.present? && number.to_s.match?(/\A\d+\z/)
    end

    # active_entries: the DegreeProgress entries of the active programs, with
    # the fields of PlanTerms. aliases: CourseCodeAlias.reviewed_pairs.
    # attempts: the best attempt of each course the student took, without
    # the ones not passed. course_details: the CourseDetails of the response.
    def initialize(active_entries, aliases: {}, attempts: [], course_details: CourseDetails.new([]))
      @active = active_entries
      @aliases = aliases
      @attempts = attempts
      @details = course_details
      @rows = {}
    end

    # The program entry with total_credits, school, and lists. A planned
    # program also gets overlap. lists is empty for a program with a plan of
    # study: its rows already name each course.
    def call(set, entry)
      lists = entry[:plan].nil? ? list_entries(set, entry[:requirements]) : []
      json = entry.merge(total_credits: entry.dig(:summary, :total_credits), school: entry.dig(:summary, :school),
                         lists: lists.map { |list| list[:json] })
      return json unless entry[:status] == "planned"

      json.merge(overlap: entry[:plan].nil? ? list_overlap(lists, entry[:program]) : plan_overlap(entry))
    end

    # The rows of a planned program that are not done, each with shared:
    # true when an active program also has the course. For a choice, one
    # shared option is enough.
    def added_rows(entry)
      rows = active_rows(entry[:program])
      entry[:requirements].reject { |row| row[:status] == "done" }.map do |row|
        { row: row, shared: row_keys(row).any? { |key| rows.any? { |active| active.keys.include?(key) } } }
      end
    end

    private

    # Each requirement row of a planned program with a plan is one needed
    # course. It is shared when an active row has the course (each active
    # row counts once), and extra when it is open and not shared. Course
    # rows match first, then choice rows, as in DegreeProgress, so a choice
    # does not use an active row that a course row needs.
    def plan_overlap(entry)
      free = active_rows(entry[:program]).dup
      shared = extra = 0
      entry[:requirements].sort_by.with_index { |row, index| [ row[:kind] == "choice" ? 1 : 0, index ] }.each do |row|
        keys = row_keys(row)
        match = free.index { |active| keys.any? { |key| active.keys.include?(key) } }
        if match
          free.delete_at(match)
          shared += 1
        elsif row[:status] == "open"
          extra += 1
        end
      end
      { shared: shared, extra: extra }
    end

    def list_overlap(lists, program)
      free = active_rows(program).dup
      counts = lists.map { |list| list_counts(list, free) }
      { shared: counts.sum(&:first), extra: counts.sum(&:last) }
    end

    # [shared, extra] of one list. The courses the student took for this
    # list count first: shared when an active program has them, else as
    # taken. Then the other list courses that an active program has are
    # shared, and the rest of the minimum is extra.
    def list_counts(list, free)
      group, row = list.values_at(:group, :row)
      return [ 0, 0 ] unless row[:checkable]

      counted = row[:courses].filter_map { |code| self.class.key(code) }
      return open_list_counts(group, counted) if open_list?(group)

      keys = group.courses.map { |course| [ course.subject_code, course.course_number ] }
      taken = keys.select { |key| counted.any? { |code| same?(key, code) } }
      needed = group.min_courses || (group.min_credits ? nil : keys.size)
      return course_counts(needed, keys, taken, free) if needed

      credit_counts(group.min_credits, keys, taken, free)
    end

    def course_counts(needed, keys, taken, free)
      shared = take_shared(taken, free) { |found| found.size >= needed }
      taken_only = [ taken.size - shared.size, needed - shared.size ].min
      shared += take_shared(keys - taken, free) { |found| shared.size + found.size + taken_only >= needed }
      [ shared.size, needed - shared.size - taken_only ]
    end

    # A list with a credit minimum: the taken courses, then the other shared
    # courses, then the open courses of the list in list order, until the
    # credits meet the minimum. When the list runs out, each further course
    # counts ASSUMED_CREDITS.
    def credit_counts(minimum, keys, taken, free)
      shared = take_shared(taken, free) { |found| credits(found) >= minimum }
      credits = credits(taken)
      more = take_shared(keys - taken, free) { |found| credits + credits(found) >= minimum }
      credits += credits(more)
      extra = 0
      (keys - taken - more).each do |key|
        break if credits >= minimum

        credits += credits_of(key)
        extra += 1
      end
      extra += ((minimum - credits) / ASSUMED_CREDITS.to_f).ceil if credits < minimum
      [ shared.size + more.size, extra ]
    end

    # A list of subjects, or of any course, names no fixed courses, so no
    # course of it is shared. The courses of its requirement row count.
    def open_list_counts(group, counted)
      if group.min_courses
        [ 0, [ group.min_courses - counted.size, 0 ].max ]
      elsif group.min_credits
        rest = group.min_credits - credits(counted)
        [ 0, rest.positive? ? (rest / ASSUMED_CREDITS.to_f).ceil : 0 ]
      else
        [ 0, 0 ]
      end
    end

    # The courses of keys that a free active row has, each row used once,
    # until the block says the found courses are enough.
    def take_shared(keys, free)
      shared = []
      keys.each do |key|
        break if yield shared

        match = free.index { |active| active.keys.include?(key) }
        next unless match

        free.delete_at(match)
        shared << key
      end
      shared
    end

    def credits(keys) = keys.sum { |key| credits_of(key) }

    # Each elective list of the program with its requirement row: the rows
    # of DegreeProgress#list_requirements are in the order of the lists.
    def list_entries(set, rows)
      set.elective_groups.zip(rows).map do |group, row|
        { group: group, row: row, json: list_json(group, row) }
      end
    end

    def list_json(group, row)
      checkable = row[:checkable]
      fixed = !open_list?(group)
      {
        name:        group.name,
        # A "Required ..." list with no minimum needs every course.
        min_courses: checkable ? group.min_courses || (fixed && group.min_credits.nil? ? group.courses.size : nil) : nil,
        min_credits: checkable ? group.min_credits : nil,
        notes:       group.notes,
        checkable:   checkable,
        courses:     list_courses(group, row, fixed).map { |key| course_json(key) }
      }
    end

    # A list of courses gives each course. A list of subjects or of any
    # course gives the courses the student took that count for it.
    def list_courses(group, row, fixed)
      return group.courses.map { |course| [ course.subject_code, course.course_number ] } if fixed

      row[:courses].filter_map { |code| self.class.key(code) }
    end

    def course_json(key)
      attempt = attempt_for(key)
      details = @details.for(key)
      {
        code:       key.join(" "),
        title:      details[:title] || attempt&.title,
        status:     attempt ? attempt.status : "open",
        term:       attempt&.term&.name,
        major_term: major_term(key)
      }
    end

    # The earliest planned term of an active row with the course, or nil.
    def major_term(key)
      @active.flat_map { |entry| active_rows_of(entry) }
             .select { |active| active.keys.include?(key) && active.term }
             .min_by(&:term_uid)&.term
    end

    def open_list?(group) = group.any_course || group.subject_codes.any?

    def attempt_for(key)
      @attempts.find { |course| same?(key, course.key) }
    end

    # A course the student took counts the credits of its section, or 0, as
    # the requirement rows count it. Any other course counts the credits of
    # CatalogCourse, or ASSUMED_CREDITS.
    def credits_of(key)
      attempt = attempt_for(key)
      return attempt.credits.to_i if attempt

      @details.for(key)[:credit_hours] || ASSUMED_CREDITS
    end

    def same?(key, other) = equivalents(key).include?(other)

    def equivalents(key) = [ key, *@aliases.fetch(key, []) ]

    # The keys a requirement row names: its code and the options of a choice.
    def row_keys(row)
      [ row[:code], *row[:options] ].compact.filter_map { |code| self.class.key(code) }
    end

    # The rows of the active programs, without the program itself: a planned
    # minor that the student also declared does not overlap with itself.
    def active_rows(program)
      @rows[program] ||= @active.reject { |entry| entry[:program] == program }.flat_map { |entry| active_rows_of(entry) }
    end

    def active_rows_of(entry)
      @rows_of ||= {}.compare_by_identity
      @rows_of[entry] ||= entry[:requirements].filter_map do |row|
        keys = [ *row_keys(row), self.class.key(row[:course]) ].compact.flat_map { |key| equivalents(key) }
        ActiveRow.new(keys.to_set, row[:planned_term], row[:planned_term_uid]) if keys.any?
      end
    end
  end
end
