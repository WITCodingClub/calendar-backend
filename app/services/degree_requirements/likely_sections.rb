# frozen_string_literal: true

module DegreeRequirements
  # Finds where a catalog course with no section of its own was likely taught.
  # The catalog year comparison (#864) lists these courses as catalog_only.
  #
  # Most of them ran under another code with the same title:
  #
  #   special_topics  a special topics number before the course got its own:
  #                   COMP 5100 Natural Language Processing ran as COMP 7800
  #   same_number     the same number in another subject, which is usually a
  #                   cross-listing: COMP 6520 Malware Analysis runs as CYBR 6520
  #   other_number    any other code with a similar title
  #
  # Only sections from the RECENT_YEARS academic years up to the catalog year
  # count. Older sections used numbers from before the 2015 renumbering (MECH
  # 255), and they say little about a catalog that is printed now.
  class LikelySections
    RECENT_YEARS = 5
    # pg_trgm similarity of the two titles, without case and without a lab
    # suffix. "Embedded Artificial Intelligen" (cut at 30 characters) and
    # "EMBEDDED ARTIFICIAL INTELLIGENCE" give 0.88.
    MIN_SIMILARITY = 0.7
    PER_COURSE = 3
    SPECIAL_TOPICS_NUMBER = 800

    Match = Data.define(:code, :title, :kind, :last_term, :sections)

    # A section title without " - Lab" or "-Lab" at the end, in lower case.
    SECTION_TITLE = "lower(regexp_replace(courses.title, '\\s*-?\\s*lab\\s*$', '', 'i'))"

    def initialize(catalog_year)
      @catalog_year = catalog_year
    end

    # rows: CourseComparison::Row values. Returns { "COMP 5100" => [Match, ...] },
    # best match first.
    def call(rows)
      courses = rows.filter_map do |row|
        subject, number = row.code.split
        [ row.code, subject, number.to_i, row.catalog_title.to_s.downcase ] if row.catalog_title.present?
      end
      return {} if courses.empty? || term_ids.empty?

      results = ActiveRecord::Base.connection.select_rows(sql(courses))
      term_names = Term.where(uid: results.map { |result| result[4] }).to_h { |term| [ term.uid, term.name ] }

      results.group_by(&:first).transform_values do |matches|
        matches.map do |_, code, number, title, last_uid, sections, catalog_number|
          Match.new(code: code, title: title, kind: kind(number.to_i, catalog_number.to_i),
                    last_term: term_names[last_uid.to_i], sections: sections.to_i)
        end
      end
    end

    private

    # The fall, spring, and summer terms of the recent academic years, the
    # catalog year included (CatalogYear.start_year_for).
    def term_ids
      @term_ids ||= begin
        last = @catalog_year.start_year
        first = last - RECENT_YEARS + 1
        Term.where(season: :fall, year: first..last)
            .or(Term.where(season: %i[spring summer], year: (first + 1)..(last + 1)))
            .ids
      end
    end

    # One row for each catalog course and each code with a similar title:
    # [catalog code, section code, section number, title, last term uid,
    # section count, catalog number].
    def sql(courses)
      connection = ActiveRecord::Base.connection
      values = courses.map do |code, subject, number, title|
        "(#{[ code, subject, title ].map { |value| connection.quote(value) }.join(', ')}, #{Integer(number)})"
      end.join(", ")
      # Each code and title once, so the titles are compared once each, not
      # once for each section.
      <<~SQL.squish
        WITH offered AS MATERIALIZED (
          SELECT #{Course::SUBJECT_CODE_SQL} || ' ' || courses.course_number AS code,
                 courses.course_number,
                 #{SECTION_TITLE} AS match_title,
                 MIN(courses.title) AS title,
                 MAX(terms.uid) AS last_uid,
                 COUNT(*) AS sections
          FROM courses
          JOIN terms ON terms.id = courses.term_id
          WHERE courses.term_id IN (#{term_ids.join(', ')})
          GROUP BY 1, 2, 3
        )
        SELECT wanted.code, found.code, found.course_number, found.title, found.last_uid, found.sections, wanted.number
        FROM (VALUES #{values}) AS wanted(code, subject, title, number)
        CROSS JOIN LATERAL (
          SELECT offered.code, offered.course_number, MIN(offered.title) AS title, MAX(offered.last_uid) AS last_uid,
                 SUM(offered.sections) AS sections, MAX(similarity(offered.match_title, wanted.title)) AS score
          FROM offered
          WHERE offered.code <> wanted.code
            AND similarity(offered.match_title, wanted.title) >= #{MIN_SIMILARITY}
          GROUP BY offered.code, offered.course_number
          ORDER BY score DESC, last_uid DESC
          LIMIT #{PER_COURSE}
        ) AS found
        ORDER BY wanted.code, found.score DESC, found.last_uid DESC
      SQL
    end

    # The query leaves out the catalog code itself, so the same number is in
    # another subject.
    def kind(number, catalog_number)
      return :special_topics if number % 1000 == SPECIAL_TOPICS_NUMBER
      return :same_number if number == catalog_number

      :other_number
    end
  end
end
