# frozen_string_literal: true

module Catalog
  # Finds the elective lists of one term (TermElectiveList rows) and their
  # courses. The REST controller and the MCP tool list_term_electives use
  # this object. docs/term-electives.md describes the data.
  class TermElectiveQuery
    class FilterError < ::Catalog::FilterError; end

    Match = Data.define(:list, :courses)

    # The lists of the term, by school and then title. With a filter, each
    # list keeps only the matching courses, and a list with no match is left
    # out.
    #
    # school: one code or more, such as "SCDS" (TermElectives::SCHOOLS).
    # course: a code, such as "COMP2000" or "COMP 2000".
    # q: words that each must be in the heading of a course.
    #
    # @return [Array<Match>]
    def call(term:, school: nil, course: nil, q: nil)
      lists = term.term_elective_lists.includes(courses: :catalog_course).order(:school, :title, :id)
      lists = lists.where(school: validated_schools(school)) if school.present?
      filters = [ course_filter(course), *heading_filters(q) ].compact

      lists.filter_map do |list|
        courses = list.courses.select { |row| filters.all? { |filter| filter.call(row) } }
        Match.new(list, courses) if filters.empty? || courses.any?
      end
    end

    private

    def validated_schools(value)
      values = Array(value).map { |v| v.to_s.strip.upcase }
      unknown = values - TermElectives::SCHOOLS
      raise FilterError, "school must be one of #{TermElectives::SCHOOLS.join(', ')}" if unknown.any?

      values
    end

    def course_filter(code)
      return if code.blank?

      subject_code, course_number = CatalogCourse.parse_code(code)
      raise FilterError, "course must be a course code, such as COMP2000" if subject_code.nil?

      ->(row) { row.subject_code == subject_code && row.course_number == course_number }
    end

    def heading_filters(q)
      q.to_s.split.map do |word|
        ->(row) { row.heading.to_s.downcase.include?(word.downcase) }
      end
    end
  end
end
