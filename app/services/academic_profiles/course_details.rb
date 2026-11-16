# frozen_string_literal: true

module AcademicProfiles
  # The CatalogCourse rows of the courses in a degree planning response (#989),
  # in one query for every key: title, description, credit hours, the terms
  # Banner usually offers each course, and its prerequisites.
  #
  # CatalogCourse has one row for each code, the same for every catalog
  # year. A key with no row takes the row of an old or new code of the same
  # course (CourseKeys), so a plan from an old catalog year still finds a
  # renumbered course.
  class CourseDetails
    UNKNOWN = { title: nil, description: nil, credit_hours: nil, typically_offered: nil }.freeze

    # The details of one CatalogCourse row, or UNKNOWN for nil. A row that
    # Catalog::CourseDetailsSync did not fill yet has no typically_offered,
    # so an empty list does not read as "never offered".
    def self.json(catalog_course)
      return UNKNOWN if catalog_course.nil?

      {
        title:             catalog_course.title,
        description:       catalog_course.description,
        credit_hours:      catalog_course.credit_hours,
        typically_offered: catalog_course.details_fetched_at ? catalog_course.typically_offered : nil
      }
    end

    # keys: the [subject_code, course_number] keys to load.
    def initialize(keys, course_keys = CourseKeys.new)
      @keys = keys.compact.uniq
      @course_keys = course_keys
    end

    def for(key) = self.class.json(catalog(key))

    # The CatalogCourse of a key or of an old or new code of it, or nil.
    def catalog(key) = @course_keys.equivalents(key).lazy.filter_map { |found| rows[found] }.first

    # The prerequisite tree of a key, or nil (no row, or no prerequisites).
    # PlanEstimate (#1011) reads it. The response does not send it.
    def prerequisites(key)
      catalog(key)&.prerequisites.presence
    end

    private

    def rows
      @rows ||= begin
        keys = @course_keys.expand(@keys)
        if keys.empty?
          {}
        else
          keys.group_by(&:first)
              .map { |subject, list| CatalogCourse.where(subject_code: subject, course_number: list.map(&:last)) }
              .reduce(:or)
              .select(:id, :subject_code, :course_number, :title, :description, :credit_hours, :typically_offered,
                      :details_fetched_at, :prerequisites)
              .index_by(&:key)
        end
      end
    end
  end
end
