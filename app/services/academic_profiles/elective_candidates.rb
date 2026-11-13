# frozen_string_literal: true

module AcademicProfiles
  # The courses of a term that can fill an elective slot or a choice of the
  # plan (#993). NextTermCourses adds them to its rows with
  # include=candidates, so a client does not pick a course that does not meet
  # the slot, such as PSYC 1500 for a slot that still needs Ethics.
  #
  # A candidate has an active section in the term. The student did not do
  # or take it (also through an alias), it is not an assumed course, and no
  # course row of the term names it. Its source depends on the row:
  #
  # - A choice: its options.
  # - A slot whose HSS category is open (hss_category): the courses in that
  #   category (HssMatcher), as DegreeProgress fills the slot.
  # - A slot whose elective list names courses or subjects: the courses that
  #   DegreeProgress#take_for accepts for the list.
  # - A slot with no list, with a list that names no course, or a free
  #   elective (any course): the courses of the term elective lists under a
  #   heading that names the slot, such as "Cryptography Elective". The
  #   catalog has nothing better for these rows. DegreeProgress cannot check
  #   such a slot (or, for a free elective, takes any course), so these
  #   candidates are only a recommendation. A free elective takes only
  #   courses for degree credit. A free elective with no such heading has no
  #   candidates, because every course of the term fills it.
  #
  # It is a recommendation, not a registration check. Banner checks
  # restrictions when the student registers.
  #
  # Queries: a fixed number for the whole response, whatever the number of
  # rows. One grouped query reads the active sections of the term, one reads
  # the catalog rows of every candidate, and one reads the term elective
  # courses.
  class ElectiveCandidates
    # The most candidates of one row. A row with more keeps the first ones
    # in the sort order.
    LIMIT = 25
    PREREQUISITE_RANK = { "met" => 0, "unknown" => 1, nil => 1, "not_met" => 2 }.freeze
    SEATS_RANK = { true => 0, nil => 1, false => 2 }.freeze
    COUNTED = %w[done in_progress].freeze
    # The school code of a term elective list (TermElectives::SCHOOLS) for
    # the school of a requirement set. A list of the HSS school, or with no
    # school, is for every program. A set of a school with no code (an old
    # college name) reads every list.
    SCHOOLS = {
      "SCDS" => /computing and data science/i,
      "SOM"  => /school of management/i,
      "SOE"  => /school of engineering/i,
      "ARCH" => /school of architecture/i,
      "SOS"  => /sciences and humanities/i
    }.freeze
    # A leading subject code in a slot label, such as "COMP" in "COMP
    # Cryptography Elective".
    LEADING_CODE = /\A[A-Z]{2,5}\s+(?=\S)/

    # A section of the term, grouped by course. open_seats is true when a
    # section has seats, false when every section with seat data has none,
    # and nil when no section has seat data.
    Offered = Struct.new(:subject_code, :course_number, :title, :credit_hours, :open_seats) do
      def key = [ subject_code, course_number ]
      def code = "#{subject_code} #{course_number}"
    end

    # term: the Term, or nil. entries: [DegreeProgress program entry, rows]
    # pairs, the rows that get candidates. taken: the courses of
    # DegreeProgress. skip: more [subject, number] pairs to leave out, such
    # as the assumed courses and the course rows of the term.
    # prerequisites: a callable that takes a CatalogCourse
    # (or nil) and gives { prerequisites:, missing:, missing_in_plan: }.
    def initialize(term:, entries:, taken:, prerequisites:, skip: [])
      @term = term
      @entries = entries
      @taken = taken
      @skip = skip
      @prerequisites = prerequisites
    end

    # The candidates of a row of an entry, sorted: prerequisites met first,
    # then unknown or no data, then not met; then open seats first; then by
    # code. At most LIMIT.
    def for(entry, row)
      pools.fetch(row, []).map { |course| candidate_json(entry, row, course) }
           .sort_by { |json| [ PREREQUISITE_RANK.fetch(json[:prerequisites]), SEATS_RANK.fetch(json[:open_seats]),
                               CatalogCourse.parse_code(json[:code]) ] }
           .first(LIMIT)
    end

    # The words of a heading or a label that name a slot: "Computer Science
    # Electives" and "Computer Science Elective" both give "computer science".
    def self.core(text)
      text.to_s.downcase.gsub(/\([^)]*\)/, " ").sub(/:.*\z/m, "").sub(/\Athe\s+/, "")
          .sub(/[\s\d]+\z/, "").sub(/\s*electives?\z/, "").sub(/[\s\d]+\z/, "").squish
    end

    private

    # The offered courses that fill each row, by row (compared by identity).
    def pools
      @pools ||= @entries.each_with_object({}.compare_by_identity) do |(entry, rows), map|
        rows.each do |row|
          test = accepts(entry, row)
          map[row] = test ? offered.select { |course| !taken?(course) && test.call(course) } : []
        end
      end
    end

    # A test of whether an offered course fills the row, or nil for no
    # candidates.
    def accepts(entry, row)
      return nil if offered.empty?
      return keys_test(row[:options].filter_map { |code| CatalogCourse.parse_code(code) }) if row[:kind] == "choice"
      return nil unless row[:kind] == "placeholder"

      category = row[:hss_category] && open_category(entry, row)
      return ->(course) { matcher.in_category?(category, course) } if category

      group = group_for(entry, row)
      if group && (group.courses.any? || group.subject_codes.any?)
        keys = keys_test(group.courses.map { |course| [ course.subject_code, course.course_number ] })
        return ->(course) { keys.call(course) || group.subject_codes.include?(course.subject_code) }
      end

      term_list_test(entry, row, group)
    end

    def keys_test(pairs)
      keys = pairs.flat_map { |pair| equivalents(pair) }.to_set
      ->(course) { keys.include?(course.key) }
    end

    # The term elective list courses under a heading that names the slot.
    def term_list_test(entry, row, group)
      names = [ group&.name, row[:label] ].compact.flat_map { |name| [ name, name.sub(LEADING_CODE, "") ] }
                                          .map { |name| self.class.core(name) }.compact_blank.uniq
      school = SCHOOLS.find { |_, pattern| pattern.match?(entry.dig(:summary, :school).to_s) }&.first
      keys = term_list_courses.select do |list_school, heading, _|
        (school.nil? || list_school.nil? || [ "HSS", school ].include?(list_school)) && names.include?(self.class.core(heading))
      end
      return nil if keys.empty?

      test = keys_test(keys.map(&:last))
      return test unless group&.any_course

      ->(course) { test.call(course) && course.subject_code != "COOP" && course.course_number >= 1000 }
    end

    # The elective list of a slot. A row names its list by name only, so
    # among the lists with that name, of the plan of the entry or of the
    # whole program, the one with the heading of the row comes first, then
    # a list of the plan, then the first by position.
    def group_for(entry, row)
      return nil if row[:elective_list].nil?

      groups = set_for(entry)&.elective_groups.to_a.select do |group|
        group.name == row[:elective_list] && (group.program_plan.nil? || group.program_plan.name == entry[:plan])
      end
      groups.to_a.min_by do |group|
        [ group.heading == row.dig(:list, :heading) ? 0 : 1, group.program_plan ? 0 : 1, group.position ]
      end
    end

    # The HSS categories of the major, or the default categories.
    def categories(entry)
      set = set_for(entry)
      set ? HssMatcher.categories(set) : DegreeRequirements::HssNoteParser.default["categories"]
    end

    def set_for(entry)
      sets[[ entry[:program], entry[:catalog_year].to_i ]]
    end

    def sets
      @sets ||= begin
        programs = @entries.map(&:first)
        if programs.empty?
          {}
        else
          RequirementSet.joins(:degree_program, :catalog_year)
                        .where(degree_programs: { slug: programs.pluck(:program).uniq },
                               catalog_years: { start_year: programs.map { |entry| entry[:catalog_year].to_i }.uniq })
                        .preload(:degree_program, :catalog_year, elective_groups: %i[courses program_plan])
                        .index_by { |set| [ set.degree_program.slug, set.catalog_year.start_year ] }
        end
      end
    end

    def candidate_json(entry, row, course)
      catalog = catalog_for(course)
      {
        code:         course.code,
        title:        catalog&.title || course.title,
        credits:      catalog&.credit_hours || course.credit_hours,
        hss_category: hss_category(entry, row, course),
        **@prerequisites.call(catalog),
        open_seats:   course.open_seats
      }
    end

    # The category of a slot that still needs one, or the first category
    # of the major that the course meets: PHIL 4501 is Ethics in an Ethics
    # slot, and Humanities elsewhere.
    def hss_category(entry, row, course)
      return row[:hss_category] if row[:hss_category] && open_category(entry, row)

      matcher.category_of(categories(entry), course)
    end

    def open_category(entry, row)
      categories(entry).find { |category| category["name"] == row[:hss_category] }
    end

    def catalog_for(course)
      equivalents(course.key).lazy.filter_map { |key| catalog_rows[key] }.first
    end

    # The catalog rows of every candidate of every row, and of their
    # aliases, in one query.
    def catalog_rows
      @catalog_rows ||= begin
        pairs = pools.values.flatten.uniq.flat_map { |course| equivalents(course.key) }.uniq
        if pairs.empty?
          {}
        else
          pairs.group_by(&:first)
               .map { |subject, list| CatalogCourse.where(subject_code: subject, course_number: list.map(&:last)) }
               .reduce(:or)
               .select(:id, :subject_code, :course_number, :title, :credit_hours, :prerequisites)
               .index_by { |row| [ row.subject_code, row.course_number ] }
        end
      end
    end

    # The courses with an active section in the term, in one grouped query.
    # A section stores its subject as a label, such as "Computer Science
    # (COMP)", so the query groups by the code in it (Course.prefix_of).
    def offered
      @offered ||= if @term.nil?
        []
      else
        subject = Arel.sql(Course::SUBJECT_CODE_SQL)
        Course.active.where(term: @term).group(subject, :course_number).order(subject, :course_number)
              .pluck(subject, :course_number, Arel.sql("MIN(courses.title)"), Arel.sql("MAX(courses.credit_hours)"),
                     Arel.sql("BOOL_OR(courses.seats_available > 0)"), Arel.sql("COUNT(courses.seats_available)"))
              .map do |subject, number, title, credits, open, with_seats|
                Offered.new(subject, number, title, credits, with_seats.zero? ? nil : open)
              end
      end
    end

    # [school, heading, [subject, number]] of each course of the term
    # elective lists of the term, in one query.
    def term_list_courses
      @term_list_courses ||= TermElectiveCourse.joins(:term_elective_list)
                                               .where(term_elective_lists: { term_id: @term.id })
                                               .where.not(heading: nil)
                                               .pluck("term_elective_lists.school", :heading, :subject_code, :course_number)
                                               .map { |school, heading, subject, number| [ school, heading, [ subject, number ] ] }
    end

    # The student did or takes the course (also through an alias), so it
    # cannot fill a slot again. A course not passed can be taken again. A
    # skipped course (assumed, or a course row of the term) is left out too.
    def taken?(course)
      equivalents(course.key).any? { |key| taken_keys.include?(key) }
    end

    def taken_keys
      @taken_keys ||= (@taken.select { |course| COUNTED.include?(course[:status]) }
                             .filter_map { |course| CatalogCourse.parse_code(course[:code]) } + @skip).to_set
    end

    def matcher
      @matcher ||= HssMatcher.new(aliases)
    end

    def equivalents(pair) = [ pair, *aliases.fetch(pair, []) ]

    # The checked aliases, as DegreeProgress reads them, so a candidate is a
    # course that DegreeProgress counts for the row.
    def aliases
      @aliases ||= CourseCodeAlias.reviewed
                                  .pluck(:from_subject_code, :from_course_number, :to_subject_code, :to_course_number)
                                  .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(fs, fn, ts, tn), map|
        map[[ fs, fn ]] << [ ts, tn ]
        map[[ ts, tn ]] << [ fs, fn ]
      end
    end
  end
end
