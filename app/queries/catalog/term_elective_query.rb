# frozen_string_literal: true

module Catalog
  # Finds the elective lists of one term (TermElectiveList rows) and their
  # courses. The REST controller and the MCP tool list_term_electives use
  # this object. docs/term-electives.md describes the data.
  class TermElectiveQuery
    Match = Data.define(:list, :courses)

    extend Filters
    filter :school, :strings, "Only the lists of these schools: #{TermElectives::SCHOOLS.join(', ')}."
    filter :course, :string, "Only this course, for example COMP2000, to see which lists name it."
    filter :q, :string, "Words in the heading, for example computer science."

    # The lists of the term, by school and then title. With a filter, each
    # list keeps only the matching courses, and a list with no match is left
    # out.
    #
    # @return [Array<Match>]
    def call(term:, **filters)
      self.class.check_filters!(filters)
      school, course, q = filters.values_at(:school, :course, :q)
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

      subject_code, course_number = CourseCode.parse(code)
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
