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
