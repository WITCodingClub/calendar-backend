# frozen_string_literal: true

module Catalog
  # Finds catalog courses (one row per course, across terms). The REST
  # controller, the GraphQL schema, and the MCP tools use this object.
  class CourseQuery
    MAX_PER_PAGE     = 100
    DEFAULT_PER_PAGE = 25

    # @return [ActiveRecord::Relation<CatalogCourse>]
    def call(q: nil, subject: nil, term_uid: nil)
      relation = CatalogCourse.all
      codes    = Array(subject).map { |code| code.to_s.strip.upcase }.reject(&:empty?)
      relation = relation.where(subject_code: codes) if codes.any?
      relation = offered_in(relation, term_uid) if term_uid.present?
      relation = search(relation, q) if q.present?
      relation.order(:subject_code, :course_number)
    end

    def find(code)
      CatalogCourse.find_by_code(code)
    end

    # A partial course code: letters, numbers, or both ("co", "COMP 23", "2350").
    PARTIAL_CODE = /\A([A-Za-z]{0,5})\s*-?\s*(\d{0,4})\z/

    # The codes ("COMP 2350") of the courses whose code starts with a partial
    # code, case-insensitive, in code order. The MCP server completes prompt
    # arguments with it. With numbers, the letters are the whole subject code,
    # so the unique index on (subject_code, course_number) finds the rows.
    #
    # @return [Array<String>] at most limit codes
    def codes_starting_with(prefix, limit:)
      match = PARTIAL_CODE.match(prefix.to_s.strip)
      return [] unless match

      letters, digits = match[1].upcase, match[2]
      relation = CatalogCourse.all
      if digits.present?
        relation = relation.where(subject_code: letters) if letters.present?
        relation = relation.where("CAST(catalog_courses.course_number AS text) LIKE ?", "#{digits}%")
      elsif letters.present?
        relation = relation.where("catalog_courses.subject_code LIKE ?", "#{letters}%")
      end

      relation.order(:subject_code, :course_number).limit(limit)
              .pluck(:subject_code, :course_number).map { |subject, number| "#{subject} #{number}" }
    end

    # The catalog courses of some sections, keyed by [subject_code, course_number],
    # so a list of sections loads them in one query.
    def self.for_sections(sections)
      pairs = sections.map { |section| [ section.prefix, section.course_number ] }.uniq
      return {} if pairs.empty?

      conditions = pairs.map { "(subject_code = ? AND course_number = ?)" }.join(" OR ")
      CatalogCourse.where(conditions, *pairs.flatten).index_by { |course| [ course.subject_code, course.course_number ] }
    end

    private

    # A code ("COMP 2350") matches that course. Other words match the title,
    # each word on its own.
    def search(relation, q)
      subject_code, course_number = CatalogCourse.parse_code(q)
      return relation.where(subject_code: subject_code, course_number: course_number) if subject_code

      q.to_s.split.reduce(relation) do |scope, word|
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(word)}%"
        scope.where("catalog_courses.title ILIKE :q OR catalog_courses.subject_code ILIKE :q", q: pattern)
      end
    end

    def offered_in(relation, term_uid)
      sections = Course.active.where(term_id: Term.where(uid: term_uid.to_i).select(:id))
      pairs = sections.distinct.pluck(:subject, :course_number).map do |subject, number|
        [ CourseDetailsSync.prefix_of(subject), number ]
      end
      return relation.none if pairs.empty?

      conditions = pairs.map { "(catalog_courses.subject_code = ? AND catalog_courses.course_number = ?)" }.join(" OR ")
      relation.where(conditions, *pairs.flatten)
    end
  end
end
