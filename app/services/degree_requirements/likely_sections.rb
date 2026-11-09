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
    # A same-number match below this score is a different course with a
    # similar title (BMED 1000 and ENGR 1000 Introduction To Engineering), not
    # a cross-listing.
    SAME_NUMBER_SIMILARITY = 0.85
    PER_COURSE = 3
    SPECIAL_TOPICS_NUMBER = 800

    Match = Data.define(:code, :title, :kind, :last_term, :sections)

    # A title without " - Lab", "-Lab", "_lab" or "Studio:Lab" at the end. Lab
    # needs a space or a mark before it, so "Matlab" stays whole.
    LAB_SUFFIX = '(\s*[-_/:]\s*|\s+)lab\s*$'
    SECTION_TITLE = "lower(regexp_replace(courses.title, '#{LAB_SUFFIX}', '', 'i'))".freeze

    # The place in a sequence at the end of a title: "Calculus II" is ii, and
    # "Power System Analysis 2" is ii too. "Calculus I" is not a match for
    # "CALCULUS II", although pg_trgm gives the pair 0.77.
    SEQUENCE = '\m(i{1,3}|iv|[1-4])\s*$'
    ROMAN = { "1" => "i", "2" => "ii", "3" => "iii", "4" => "iv" }.freeze

    def initialize(catalog_year)
      @catalog_year = catalog_year
    end

    # rows: CourseComparison::Row values. Returns { "COMP 5100" => [Match, ...] },
    # best match first.
    def call(rows)
      courses = rows.filter_map do |row|
        subject, number = row.code.split
        next if row.catalog_title.blank?

        title = row.catalog_title.downcase.sub(%r{(\s*[-_/:]\s*|\s+)lab\s*\z}, "")
        [ row.code, subject, number.to_i, title, sequence(title) ]
      end
      return {} if courses.empty? || term_ids.empty?

      results = ActiveRecord::Base.connection.select_rows(sql(courses))
      term_names = Term.where(uid: results.map { |result| result[4] }).to_h { |term| [ term.uid, term.name ] }

      results.group_by(&:first).transform_values do |matches|
        matches.map do |_, code, number, title, last_uid, sections, catalog_number, score|
          Match.new(code: code, title: title, kind: kind(number.to_i, catalog_number.to_i, score.to_f),
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

    # One row for each catalog course and each code with a similar title and
    # the same place in a sequence: [catalog code, section code, section
    # number, title, last term uid, section count, catalog number, score].
    def sql(courses)
      connection = ActiveRecord::Base.connection
      values = courses.map do |code, subject, number, title, sequence|
        "(#{[ code, subject, title, sequence ].map { |value| connection.quote(value) }.join(', ')}, #{Integer(number)})"
      end.join(", ")
      roman = ROMAN.map { |digit, numeral| "WHEN '#{digit}' THEN '#{numeral}'" }.join(" ")
      # Each code and title once, so the titles are compared once each, not
      # once for each section.
      <<~SQL.squish
        WITH offered AS MATERIALIZED (
          SELECT #{Course::SUBJECT_CODE_SQL} || ' ' || courses.course_number AS code,
                 courses.course_number,
                 #{SECTION_TITLE} AS match_title,
                 COALESCE(CASE SUBSTRING(#{SECTION_TITLE} FROM '#{SEQUENCE}') #{roman}
                          ELSE SUBSTRING(#{SECTION_TITLE} FROM '#{SEQUENCE}') END, '') AS sequence,
                 MIN(courses.title) AS title,
                 MAX(terms.uid) AS last_uid,
                 COUNT(*) AS sections
          FROM courses
          JOIN terms ON terms.id = courses.term_id
          WHERE courses.term_id IN (#{term_ids.join(', ')})
          GROUP BY 1, 2, 3, 4
        )
        SELECT wanted.code, found.code, found.course_number, found.title, found.last_uid, found.sections, wanted.number,
               found.score
        FROM (VALUES #{values}) AS wanted(code, subject, title, sequence, number)
        CROSS JOIN LATERAL (
          SELECT offered.code, offered.course_number, MIN(offered.title) AS title, MAX(offered.last_uid) AS last_uid,
                 SUM(offered.sections) AS sections, MAX(similarity(offered.match_title, wanted.title)) AS score
          FROM offered
          WHERE offered.code <> wanted.code
            AND offered.sequence = wanted.sequence
            AND similarity(offered.match_title, wanted.title) >= #{MIN_SIMILARITY}
          GROUP BY offered.code, offered.course_number
          ORDER BY score DESC, last_uid DESC
          LIMIT #{PER_COURSE}
        ) AS found
        ORDER BY wanted.code, found.score DESC, found.last_uid DESC
      SQL
    end

    def sequence(title)
      token = title[/\b(i{1,3}|iv|[1-4])\s*\z/, 1].to_s
      ROMAN.fetch(token, token)
    end

    # The query leaves out the catalog code itself, so the same number is in
    # another subject.
    def kind(number, catalog_number, score)
      return :special_topics if number % 1000 == SPECIAL_TOPICS_NUMBER
      return :same_number if number == catalog_number && score >= SAME_NUMBER_SIMILARITY

      :other_number
    end
  end
end
