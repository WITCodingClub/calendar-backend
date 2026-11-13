# frozen_string_literal: true

module AcademicProfiles
  # The catalog details of the courses in a degree progress response (#989):
  # title, description, credit hours, and the terms Banner usually offers
  # each course. They come from CatalogCourse, in one query for every code.
  #
  # CatalogCourse has one row for each code, the same for every catalog
  # year. A code with no row takes the row of an old or new code of the same
  # course (CourseCodeAlias), so a plan from an old catalog year still finds
  # a renumbered course.
  class CourseDetails
    # The details of a code that CatalogCourse does not know.
    UNKNOWN = { title: nil, description: nil, credit_hours: nil, typically_offered: nil }.freeze

    # The details of one CatalogCourse row, or UNKNOWN for nil.
    def self.json(catalog_course)
      return UNKNOWN if catalog_course.nil?

      {
        title:             catalog_course.title,
        description:       catalog_course.description,
        credit_hours:      catalog_course.credit_hours,
        typically_offered: catalog_course.typically_offered
      }
    end

    # codes: [subject_code, course_number] pairs. aliases: each pair with the
    # pairs of its old and new codes.
    def initialize(codes, aliases = {})
      @codes = codes.compact.uniq
      @aliases = aliases
    end

    # The details of a [subject_code, course_number] pair, from its own row
    # or the row of an alias.
    def for(pair)
      self.class.json(keys(pair).lazy.filter_map { |key| rows[key] }.first)
    end

    private

    def keys(pair) = [ pair, *@aliases.fetch(pair, []) ]

    def rows
      @rows ||= begin
        pairs = @codes.flat_map { |pair| keys(pair) }.uniq
        if pairs.empty?
          {}
        else
          pairs.group_by(&:first)
               .map { |subject, list| CatalogCourse.where(subject_code: subject, course_number: list.map(&:last)) }
               .reduce(:or)
               .select(:id, :subject_code, :course_number, :title, :description, :credit_hours, :typically_offered)
               .index_by { |row| [ row.subject_code, row.course_number ] }
        end
      end
    end
  end
end
